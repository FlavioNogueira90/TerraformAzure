terraform {
  required_version = ">= 0.13"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 2.26"
    }
  }
}

provider "azurerm" {
  skip_provider_registration = true
  features {}
}
# Cria o resource group
resource "azurerm_resource_group" "rg-aula-fs" {
  name     = "rg-aula-fs"
  location = "eastus"
}
# Cria rede virtual
resource "azurerm_virtual_network" "vn-aula-fs" {
  name                = "vn-aula-fs"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg-aula-fs.location
  resource_group_name = azurerm_resource_group.rg-aula-fs.name
  
  tags = {
    "faculdade" = "impacta"
  }
}
# Cria SubNet
resource "azurerm_subnet" "sub-aula-fs" {
  name                 = "sub-aula-fs"
  resource_group_name  = azurerm_resource_group.rg-aula-fs.name
  virtual_network_name = azurerm_virtual_network.vn-aula-fs.name
  address_prefixes     = ["10.0.1.0/24"]
}
# Cria IP publico
resource "azurerm_public_ip" "ip-aula-fs" {
  name                = "ip-aula-fs"
  resource_group_name = azurerm_resource_group.rg-aula-fs.name
  location            = azurerm_resource_group.rg-aula-fs.location
  allocation_method   = "Static"

  tags = {
    environment = "Production"
    turma       = "fs"
    sistema     = "abc"
  }
}
# Cria um data para armazenar o ip gerado, será utilizado posteriormente
data "azurerm_public_ip" "data-ip-aula-fs" {
  resource_group_name = azurerm_resource_group.rg-aula-fs.name
  name                = azurerm_public_ip.ip-aula-fs.name
}

# Cria um Security group
resource "azurerm_network_security_group" "nsg-aula-fs" {
  name                = "nsg-aula-fs"
  location            = azurerm_resource_group.rg-aula-fs.location
  resource_group_name = azurerm_resource_group.rg-aula-fs.name

  # Regra de segurança para o que será trafegado
  security_rule {
    name                       = "mysql"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3306"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "SSH"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    environment = "Production"
  }
}
# Cria intereface de rede
resource "azurerm_network_interface" "ni-aula-fs" {
  name                = "ni-aula-fs"
  location            = azurerm_resource_group.rg-aula-fs.location
  resource_group_name = azurerm_resource_group.rg-aula-fs.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.sub-aula-fs.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.ip-aula-fs.id
  }
}

# Cria a associação entre a interface de rede e o Security group
resource "azurerm_network_interface_security_group_association" "nisga-aula-fs" {
  network_interface_id      = azurerm_network_interface.ni-aula-fs.id
  network_security_group_id = azurerm_network_security_group.nsg-aula-fs.id
}
# Cria storage
resource "azurerm_storage_account" "sa-aula-fs" {
  name                      = "storageaccoutmyvm"
  resource_group_name       = azurerm_resource_group.rg-aula-fs.name
  location                  = azurerm_resource_group.rg-aula-fs.location
  account_tier              = "Standard" 
  account_replication_type  = "LRS"
}

# Cria a VM
resource "azurerm_linux_virtual_machine" "vm-aula-fs" {
  name                  = "vm-aula-fs"
  location              = azurerm_resource_group.rg-aula-fs.location
  resource_group_name   = azurerm_resource_group.rg-aula-fs.name
  network_interface_ids = [azurerm_network_interface.ni-aula-fs.id]
  size                  = "Standard_DS1_v2"

  os_disk {
    name                  = "dsk-aula-fs"
    caching               = "ReadWrite"
    storage_account_type  = "Premium_LRS"
  }
  
  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  computer_name  = "vm-aula-fs"
  admin_username = "testadmin"
  admin_password = "Password1234!"
  disable_password_authentication = false
  
  boot_diagnostics {
    storage_account_uri = azurerm_storage_account.sa-aula-fs.primary_blob_endpoint
  }

  depends_on = [
    azurerm_resource_group.rg-aula-fs
  ]
}

# Ao término do processo, mostra o IP publico criado
output "publicip-vm-aula-fs" {
  value = azurerm_public_ip.ip-aula-fs.ip_address
}

# Adicionar delay de 30 segundos após a criação da VM para iniciar a instalação 
resource "time_sleep" "esperar_30_segundos" {
  depends_on = [
    azurerm_linux_virtual_machine.vm-aula-fs
  ]
  create_duration = "30s"
}
# Instalar o mysql na VM criada, aqui precisa ter o ip gravado no data
# Essa ação deverá depender do delay acima, justamente para rodar após 30 segundos da criação da VM
resource "null_resource" "upload_db" {
  provisioner "file" {
    connection {
      type     = "ssh"
      user     = "testadmin"
      password = "Password1234!"
      host     = data.azurerm_public_ip.data-ip-aula-fs.ip_address
    }
    source = "config"
    destination = "/home/azureuser"
  }
  # Adicionandoa a dependencia
  depends_on = [time_sleep.esperar_30_segundos]
}
# Após a execução do comando acima, será executado esse abaixo
resource "null_resource" "deploy_db" {
  triggers = {
    order = null_resource.upload_db.id
  }
  provisioner "remote-exec" {
    connection {
      type     = "ssh"
      user     = "testadmin"
      password = "Password1234!"    
      host     = data.azurerm_public_ip.data-ip-aula-fs.ip_address
    }
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y mysql-server-5.7",
      "sudo mysql < /home/azureuser/config/user.sql",
      "sudo cp -f /home/azureuser/config/mysqld.cnf /etc/mysql/mysql.conf.d/mysqld.cnf",
      "sudo service mysql restart",
      "sleep 20",
    ]
  }
}
