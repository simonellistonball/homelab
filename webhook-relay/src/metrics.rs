use axum::http::StatusCode;
use axum::response::IntoResponse;
use lazy_static::lazy_static;
use prometheus::{
    register_counter, register_counter_vec, register_histogram_vec, Counter, CounterVec, Encoder,
    HistogramVec, TextEncoder,
};

lazy_static! {
    pub static ref MESSAGES_RECEIVED: Counter = register_counter!(
        "webhook_relay_messages_received_total",
        "Total number of messages received from SQS"
    )
    .unwrap();
    pub static ref MESSAGES_FORWARDED: CounterVec = register_counter_vec!(
        "webhook_relay_messages_forwarded_total",
        "Total number of messages forwarded to targets",
        &["target", "status"]
    )
    .unwrap();
    pub static ref MESSAGES_FAILED: CounterVec = register_counter_vec!(
        "webhook_relay_messages_failed_total",
        "Total number of messages that failed to process",
        &["target", "reason"]
    )
    .unwrap();
    pub static ref FORWARD_DURATION: HistogramVec = register_histogram_vec!(
        "webhook_relay_forward_duration_seconds",
        "Time spent forwarding webhooks to targets",
        &["target"],
        vec![0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0]
    )
    .unwrap();
}

pub async fn handler() -> impl IntoResponse {
    let encoder = TextEncoder::new();
    let metric_families = prometheus::gather();

    let mut buffer = Vec::new();
    if let Err(e) = encoder.encode(&metric_families, &mut buffer) {
        return (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Failed to encode metrics: {}", e),
        )
            .into_response();
    }

    match String::from_utf8(buffer) {
        Ok(output) => (
            StatusCode::OK,
            [("content-type", "text/plain; version=0.0.4")],
            output,
        )
            .into_response(),
        Err(e) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            format!("Failed to convert metrics to string: {}", e),
        )
            .into_response(),
    }
}
