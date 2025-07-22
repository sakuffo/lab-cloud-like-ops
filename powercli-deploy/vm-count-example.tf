# Example: Using count in VM names

# Method 1: Using count.index directly
resource "azurerm_virtual_machine" "example" {
  count               = 3
  name                = "vm-web-${count.index + 1}"  # Creates: vm-web-1, vm-web-2, vm-web-3
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
  # ... other VM configuration
}

# Method 2: Using format function for padding
resource "azurerm_virtual_machine" "database" {
  count               = 5
  name                = format("vm-db-%02d", count.index + 1)  # Creates: vm-db-01, vm-db-02, etc.
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
  # ... other VM configuration
}

# Method 3: Using variables with count
variable "vm_names" {
  default = ["web-server", "app-server", "db-server"]
}

resource "azurerm_virtual_machine" "named" {
  count               = length(var.vm_names)
  name                = "vm-${var.vm_names[count.index]}"  # Creates: vm-web-server, vm-app-server, vm-db-server
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
  # ... other VM configuration
}

# Method 4: Environment-based naming
variable "environment" {
  default = "prod"
}

resource "azurerm_virtual_machine" "env_based" {
  count               = 2
  name                = "${var.environment}-vm-${count.index + 1}"  # Creates: prod-vm-1, prod-vm-2
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
  # ... other VM configuration
}