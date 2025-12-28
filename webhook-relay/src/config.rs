use anyhow::{Context, Result};
use std::env;

#[derive(Debug, Clone)]
pub struct Config {
    // AWS Configuration
    pub aws_region: String,
    pub sqs_queue_url: String,

    // Polling Configuration
    pub poll_interval_ms: u64,
    pub max_messages: i32,

    // Routing Configuration
    pub route_config_path: String,

    // Server Configuration
    pub http_port: u16,
    pub metrics_port: u16,
}

impl Config {
    pub fn from_env() -> Result<Self> {
        Ok(Config {
            aws_region: env::var("AWS_REGION")
                .or_else(|_| env::var("AWS_DEFAULT_REGION"))
                .unwrap_or_else(|_| "us-east-1".to_string()),

            sqs_queue_url: env::var("SQS_QUEUE_URL")
                .context("SQS_QUEUE_URL environment variable is required")?,

            poll_interval_ms: env::var("POLL_INTERVAL_MS")
                .unwrap_or_else(|_| "1000".to_string())
                .parse()
                .context("POLL_INTERVAL_MS must be a valid number")?,

            max_messages: env::var("MAX_MESSAGES")
                .unwrap_or_else(|_| "10".to_string())
                .parse()
                .context("MAX_MESSAGES must be a valid number")?,

            route_config_path: env::var("ROUTE_CONFIG_PATH")
                .unwrap_or_else(|_| "/config/routes.yaml".to_string()),

            http_port: env::var("HTTP_PORT")
                .unwrap_or_else(|_| "8080".to_string())
                .parse()
                .context("HTTP_PORT must be a valid port number")?,

            metrics_port: env::var("METRICS_PORT")
                .unwrap_or_else(|_| "9090".to_string())
                .parse()
                .context("METRICS_PORT must be a valid port number")?,
        })
    }
}
