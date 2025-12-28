use anyhow::{anyhow, Context, Result};
use serde::Deserialize;
use std::collections::HashMap;
use std::fs;

#[derive(Debug, Clone)]
pub struct RouteTarget {
    pub name: String,
    pub url: String,
    pub timeout_seconds: u64,
}

#[derive(Debug, Deserialize)]
struct RoutesConfig {
    routes: HashMap<String, RouteEntry>,
    #[serde(default)]
    default: Option<DefaultAction>,
}

#[derive(Debug, Deserialize)]
struct RouteEntry {
    url: String,
    #[serde(default = "default_timeout")]
    timeout_seconds: u64,
}

#[derive(Debug, Deserialize)]
struct DefaultAction {
    action: String,
    #[serde(default)]
    url: Option<String>,
}

fn default_timeout() -> u64 {
    30
}

pub struct WebhookRouter {
    routes: HashMap<String, RouteTarget>,
    default_action: String,
    default_url: Option<String>,
}

impl WebhookRouter {
    pub fn from_file(path: &str) -> Result<Self> {
        let content = fs::read_to_string(path)
            .with_context(|| format!("Failed to read routes config from {}", path))?;

        Self::from_yaml(&content)
    }

    pub fn from_yaml(yaml: &str) -> Result<Self> {
        let config: RoutesConfig =
            serde_yaml::from_str(yaml).context("Failed to parse routes YAML")?;

        let routes = config
            .routes
            .into_iter()
            .map(|(name, entry)| {
                (
                    name.clone(),
                    RouteTarget {
                        name,
                        url: entry.url,
                        timeout_seconds: entry.timeout_seconds,
                    },
                )
            })
            .collect();

        let (default_action, default_url) = match config.default {
            Some(d) => (d.action, d.url),
            None => ("drop".to_string(), None),
        };

        Ok(WebhookRouter {
            routes,
            default_action,
            default_url,
        })
    }

    pub fn route_count(&self) -> usize {
        self.routes.len()
    }

    /// Route a webhook path to a target
    /// Returns (target, remaining_path)
    pub fn route(&self, path: &str) -> Result<(&RouteTarget, String)> {
        // Parse path: /webhook/<service>/<rest>
        let parts: Vec<&str> = path.trim_start_matches('/').split('/').collect();

        // Expect at least: webhook, service
        if parts.len() < 2 || parts[0] != "webhook" {
            return Err(anyhow!("Invalid path format: {}", path));
        }

        let service = parts[1];
        let rest_path = if parts.len() > 2 {
            format!("/{}", parts[2..].join("/"))
        } else {
            "/".to_string()
        };

        if let Some(target) = self.routes.get(service) {
            return Ok((target, rest_path));
        }

        // Handle default action
        match self.default_action.as_str() {
            "forward" => {
                if let Some(ref url) = self.default_url {
                    // Create a temporary default target
                    // This is a bit hacky - in production we'd handle this better
                    Err(anyhow!(
                        "Default forwarding not fully implemented. URL: {}",
                        url
                    ))
                } else {
                    Err(anyhow!("No route found for service: {}", service))
                }
            }
            "drop" | _ => Err(anyhow!("No route found for service: {} (dropping)", service)),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_route_parsing() {
        let yaml = r#"
routes:
  n8n:
    url: "https://n8n.example.com"
    timeout_seconds: 30
  gitea:
    url: "https://gitea.example.com"

default:
  action: drop
"#;

        let router = WebhookRouter::from_yaml(yaml).unwrap();

        // Test n8n route
        let (target, rest) = router.route("/webhook/n8n/my-workflow").unwrap();
        assert_eq!(target.name, "n8n");
        assert_eq!(target.url, "https://n8n.example.com");
        assert_eq!(rest, "/my-workflow");

        // Test gitea route
        let (target, rest) = router.route("/webhook/gitea/push").unwrap();
        assert_eq!(target.name, "gitea");
        assert_eq!(rest, "/push");

        // Test unknown route
        assert!(router.route("/webhook/unknown/test").is_err());
    }
}
