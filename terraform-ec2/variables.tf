# Ingress port numbers for secur4ity group
variable "sg_ports" {
  type        = list(number)
  description = "list of ingress ports"
  default     = [8080, 9000, 22]
}