use axum::{http::StatusCode, response::IntoResponse, Json};
use serde::Serialize;
use std::sync::Arc;

use crate::sqs::SqsConsumer;

#[derive(Serialize)]
struct HealthResponse {
    status: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    message: Option<String>,
}

/// Liveness probe - returns 200 if the service is running
pub async fn liveness() -> impl IntoResponse {
    Json(HealthResponse {
        status: "ok".to_string(),
        message: None,
    })
}

/// Readiness probe - checks SQS connectivity
pub async fn readiness(sqs: Arc<SqsConsumer>) -> impl IntoResponse {
    match sqs.check_connectivity().await {
        Ok(_) => (
            StatusCode::OK,
            Json(HealthResponse {
                status: "ready".to_string(),
                message: None,
            }),
        ),
        Err(e) => (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(HealthResponse {
                status: "not_ready".to_string(),
                message: Some(format!("SQS connectivity failed: {}", e)),
            }),
        ),
    }
}
