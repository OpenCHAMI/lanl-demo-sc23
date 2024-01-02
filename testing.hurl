PUT http://localhost:27779/hsm/v2/State/Components/x0c0s1b0n3
{
  "Component": {
    "State": "Ready",
    "Enabled": true,
    "Role": "Compute",
    "NID": 3,
    "Arch": "X86",
    "Class": "Mountain"
  }
}
HTTP 204

PUT http://localhost:27779/hsm/v2/State/Components/x0c0s1b0
{
  "Component": {
    "Type": "NodeBMC",
    "State": "Ready",
    "Enabled": true
  }
}
HTTP 204

PUT http://localhost:27779/hsm/v2/State/Components/x0c0s1b1
{
  "Component": {
    "Type": "NodeBMC",
    "State": "Ready",
    "Enabled": true
  }
}
HTTP 204

PUT http://localhost:27779/hsm/v2/State/Components/x0c0s1b2
{
  "Component": {
    "Type": "NodeBMC",
    "State": "Ready",
    "Enabled": true
  }
}
HTTP 204

PUT http://localhost:27779/hsm/v2/State/Components/x0c0s1b3
{
  "Component": {
    "Type": "NodeBMC",
     "State": "Ready"
  }
}
HTTP 204

GET http://localhost:27779/hsm/v2/State/Components

# Create SMD Redfish endpoints for first xname.
POST http://localhost:27779/hsm/v2/Inventory/RedfishEndpoints
{
	"ID": "x0c0s1b0",
	"Name": "x0c0s1b0",
	"Hostname": "x0c0s1b0",
	"FQDN": "",
	"User": "admin",
	"Password": "password",
	"MACRequired": true,
	"RediscoverOnUpdate": false,
	"MACAddr": "ae:12:e2:ff:89:9d",
	"IPAddress": "10.254.2.10"
}
HTTP 201

# Create SMD Redfish endpoints for third xname (the second will be deleted).
POST http://localhost:27779/hsm/v2/Inventory/RedfishEndpoints
{
	"ID": "x0c0s3b0",
	"Name": "x0c0s3b0",
	"Hostname": "x0c0s3b0",
	"FQDN": "",
	"User": "admin",
	"Password": "password",
	"MACRequired": true,
	"RediscoverOnUpdate": false,
	"MACAddr": "ae:12:e2:ff:89:9e",
	"IPAddress": "10.254.2.11"
}
HTTP 201

GET http://localhost:8080/v1/ochami/physical/BMCs
HTTP 200

