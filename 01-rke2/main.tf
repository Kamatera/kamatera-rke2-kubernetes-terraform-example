terraform {
  required_providers {
    kamatera = {
      source = "Kamatera/kamatera"
    }
  }
}

provider "kamatera" {
  api_client_id = var.kamatera_api_client_id
  api_secret    = var.kamatera_api_secret
}
