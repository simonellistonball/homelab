use anyhow::Result;
use aws_sdk_sqs::{types::Message, Client};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

use crate::config::Config;

pub struct SqsConsumer {
    client: Client,
    queue_url: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct WebhookMessage {
    pub path: String,
    pub method: String,
    pub headers: HashMap<String, String>,
    pub body: String,
    #[serde(default)]
    pub is_base64_encoded: bool,
    #[serde(default)]
    pub query_string_parameters: HashMap<String, String>,
    pub timestamp: String,
    #[serde(default)]
    pub source_ip: String,
}

impl SqsConsumer {
    pub async fn new(config: &Config) -> Result<Self> {
        let aws_config = aws_config::from_env()
            .region(aws_config::Region::new(config.aws_region.clone()))
            .load()
            .await;

        let client = Client::new(&aws_config);

        Ok(SqsConsumer {
            client,
            queue_url: config.sqs_queue_url.clone(),
        })
    }

    pub async fn receive_messages(&self, max_messages: i32) -> Result<Vec<Message>> {
        let response = self
            .client
            .receive_message()
            .queue_url(&self.queue_url)
            .max_number_of_messages(max_messages)
            .wait_time_seconds(20) // Long polling
            .visibility_timeout(60)
            .send()
            .await?;

        Ok(response.messages.unwrap_or_default())
    }

    pub async fn delete_message(&self, receipt_handle: &str) -> Result<()> {
        self.client
            .delete_message()
            .queue_url(&self.queue_url)
            .receipt_handle(receipt_handle)
            .send()
            .await?;

        Ok(())
    }

    pub async fn check_connectivity(&self) -> Result<()> {
        self.client
            .get_queue_attributes()
            .queue_url(&self.queue_url)
            .attribute_names(aws_sdk_sqs::types::QueueAttributeName::ApproximateNumberOfMessages)
            .send()
            .await?;

        Ok(())
    }
}
