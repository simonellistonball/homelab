use anyhow::{Context, Result};
use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
use reqwest::{header::HeaderMap, header::HeaderName, header::HeaderValue, Client, StatusCode};
use std::time::Duration;

use crate::config::Config;
use crate::router::RouteTarget;
use crate::sqs::WebhookMessage;

pub struct Forwarder {
    client: Client,
}

impl Forwarder {
    pub fn new(_config: &Config) -> Result<Self> {
        let client = Client::builder()
            .timeout(Duration::from_secs(60))
            .connect_timeout(Duration::from_secs(10))
            .pool_max_idle_per_host(10)
            .build()
            .context("Failed to create HTTP client")?;

        Ok(Forwarder { client })
    }

    pub async fn forward(
        &self,
        message: &WebhookMessage,
        target: &RouteTarget,
        rest_path: &str,
    ) -> Result<StatusCode> {
        // Build the target URL
        let url = format!("{}{}", target.url.trim_end_matches('/'), rest_path);

        // Build query string if present
        let url = if !message.query_string_parameters.is_empty() {
            let query: Vec<String> = message
                .query_string_parameters
                .iter()
                .map(|(k, v)| format!("{}={}", k, v))
                .collect();
            format!("{}?{}", url, query.join("&"))
        } else {
            url
        };

        // Decode body if base64 encoded
        let body = if message.is_base64_encoded {
            match BASE64.decode(&message.body) {
                Ok(decoded) => decoded,
                Err(_) => message.body.as_bytes().to_vec(),
            }
        } else {
            message.body.as_bytes().to_vec()
        };

        // Build headers
        let mut headers = HeaderMap::new();
        for (key, value) in &message.headers {
            // Skip hop-by-hop headers and some that shouldn't be forwarded
            let key_lower = key.to_lowercase();
            if matches!(
                key_lower.as_str(),
                "host"
                    | "connection"
                    | "keep-alive"
                    | "proxy-authenticate"
                    | "proxy-authorization"
                    | "te"
                    | "trailers"
                    | "transfer-encoding"
                    | "upgrade"
                    | "content-length"
            ) {
                continue;
            }

            if let (Ok(name), Ok(val)) = (
                HeaderName::try_from(key.as_str()),
                HeaderValue::try_from(value.as_str()),
            ) {
                headers.insert(name, val);
            }
        }

        // Add our own headers
        if let Ok(val) = HeaderValue::try_from(&message.source_ip) {
            headers.insert("X-Forwarded-For", val);
        }
        headers.insert(
            "X-Webhook-Relay",
            HeaderValue::from_static("webhook-relay/1.0"),
        );

        // Build the request
        let request = match message.method.to_uppercase().as_str() {
            "GET" => self.client.get(&url).headers(headers),
            "POST" => self.client.post(&url).headers(headers).body(body),
            "PUT" => self.client.put(&url).headers(headers).body(body),
            "PATCH" => self.client.patch(&url).headers(headers).body(body),
            "DELETE" => self.client.delete(&url).headers(headers),
            _ => self.client.post(&url).headers(headers).body(body),
        };

        // Set timeout from target config
        let request = request.timeout(Duration::from_secs(target.timeout_seconds));

        // Send the request
        let response = request
            .send()
            .await
            .with_context(|| format!("Failed to forward webhook to {}", url))?;

        Ok(response.status())
    }
}
