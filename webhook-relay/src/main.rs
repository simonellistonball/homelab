mod config;
mod forwarder;
mod health;
mod metrics;
mod router;
mod sqs;

use anyhow::Result;
use axum::{routing::get, Router};
use std::sync::Arc;
use tokio::net::TcpListener;
use tracing::info;
use tracing_subscriber::{fmt, prelude::*, EnvFilter};

use crate::config::Config;
use crate::forwarder::Forwarder;
use crate::router::WebhookRouter;
use crate::sqs::SqsConsumer;

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize logging
    let filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info"));

    tracing_subscriber::registry()
        .with(fmt::layer().with_target(true))
        .with(filter)
        .init();

    info!("Starting webhook-relay...");

    // Load configuration
    let config = Config::from_env()?;
    info!("Configuration loaded");
    info!("  SQS Queue: {}", config.sqs_queue_url);
    info!("  HTTP Port: {}", config.http_port);
    info!("  Metrics Port: {}", config.metrics_port);

    // Load routing configuration
    let router = WebhookRouter::from_file(&config.route_config_path)?;
    let router = Arc::new(router);
    info!("Routes loaded: {} configured", router.route_count());

    // Create HTTP client for forwarding
    let forwarder = Forwarder::new(&config)?;
    let forwarder = Arc::new(forwarder);

    // Create SQS consumer
    let sqs_consumer = SqsConsumer::new(&config).await?;
    let sqs_consumer = Arc::new(sqs_consumer);
    info!("SQS consumer initialized");

    // Start the HTTP server for health checks
    let health_app = Router::new()
        .route("/health", get(health::liveness))
        .route("/ready", get({
            let sqs = Arc::clone(&sqs_consumer);
            move || health::readiness(sqs.clone())
        }));

    let http_listener = TcpListener::bind(format!("0.0.0.0:{}", config.http_port)).await?;
    info!("Health server listening on port {}", config.http_port);

    // Start the metrics server
    let metrics_app = Router::new().route("/metrics", get(metrics::handler));

    let metrics_listener = TcpListener::bind(format!("0.0.0.0:{}", config.metrics_port)).await?;
    info!("Metrics server listening on port {}", config.metrics_port);

    // Spawn servers
    let http_handle = tokio::spawn(async move {
        axum::serve(http_listener, health_app).await
    });

    let metrics_handle = tokio::spawn(async move {
        axum::serve(metrics_listener, metrics_app).await
    });

    // Start the SQS polling loop
    let poll_interval = std::time::Duration::from_millis(config.poll_interval_ms);
    let max_messages = config.max_messages;

    info!("Starting SQS polling loop (interval: {:?}, max_messages: {})", poll_interval, max_messages);

    let poll_handle = tokio::spawn(async move {
        loop {
            match sqs_consumer.receive_messages(max_messages).await {
                Ok(messages) => {
                    if !messages.is_empty() {
                        info!("Received {} messages from SQS", messages.len());
                        metrics::MESSAGES_RECEIVED.inc_by(messages.len() as f64);
                    }

                    for msg in messages {
                        let receipt_handle = match &msg.receipt_handle {
                            Some(h) => h.clone(),
                            None => {
                                tracing::warn!("Message without receipt handle, skipping");
                                continue;
                            }
                        };

                        let body = match &msg.body {
                            Some(b) => b.clone(),
                            None => {
                                tracing::warn!("Message without body, skipping");
                                continue;
                            }
                        };

                        // Process the message
                        match process_message(&body, &router, &forwarder).await {
                            Ok(()) => {
                                // Delete the message from SQS
                                if let Err(e) = sqs_consumer.delete_message(&receipt_handle).await {
                                    tracing::error!("Failed to delete message: {}", e);
                                }
                            }
                            Err(e) => {
                                tracing::error!("Failed to process message: {}", e);
                                metrics::MESSAGES_FAILED
                                    .with_label_values(&["unknown", "processing_error"])
                                    .inc();
                                // Message will return to queue after visibility timeout
                            }
                        }
                    }
                }
                Err(e) => {
                    tracing::error!("Failed to receive messages: {:?}", e);
                    tokio::time::sleep(std::time::Duration::from_secs(5)).await;
                }
            }

            tokio::time::sleep(poll_interval).await;
        }
    });

    // Wait for any task to complete (shouldn't happen normally)
    tokio::select! {
        _ = http_handle => tracing::error!("HTTP server exited"),
        _ = metrics_handle => tracing::error!("Metrics server exited"),
        _ = poll_handle => tracing::error!("Polling loop exited"),
    }

    Ok(())
}

async fn process_message(
    body: &str,
    router: &WebhookRouter,
    forwarder: &Forwarder,
) -> Result<()> {
    // Parse the message
    let webhook: sqs::WebhookMessage = serde_json::from_str(body)?;

    // Extract the target service from the path
    // Path format: /webhook/<service>/<rest>
    let (target, rest_path) = router.route(&webhook.path)?;

    info!(
        "Routing webhook: {} -> {} (path: {})",
        webhook.path, target.url, rest_path
    );

    let timer = metrics::FORWARD_DURATION
        .with_label_values(&[&target.name])
        .start_timer();

    // Forward the webhook
    match forwarder.forward(&webhook, target, &rest_path).await {
        Ok(status) => {
            timer.observe_duration();
            metrics::MESSAGES_FORWARDED
                .with_label_values(&[&target.name, &status.to_string()])
                .inc();

            if status.is_success() {
                info!("Webhook forwarded successfully: {}", status);
                Ok(())
            } else {
                tracing::warn!("Webhook forwarded but got error response: {}", status);
                // Still consider it processed - the target received it
                Ok(())
            }
        }
        Err(e) => {
            timer.observe_duration();
            metrics::MESSAGES_FAILED
                .with_label_values(&[&target.name, "forward_error"])
                .inc();
            Err(e)
        }
    }
}
