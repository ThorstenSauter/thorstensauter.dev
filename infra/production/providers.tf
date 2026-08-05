provider "azurerm" {
  storage_use_azuread = true
  resource_providers_to_register = [
    "Microsoft.Web",
  ]
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

provider "cloudflare" {}

