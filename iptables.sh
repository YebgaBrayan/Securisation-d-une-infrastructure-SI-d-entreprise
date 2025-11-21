#!/bin/bash

 Variables d’interface (à adapter)
WAN_IF="enp0s3"        # Interface vers Internet
LAN_IF="enp0s8"        # Interface interne

 Plages réseau (à adapter)
VLAN_USERS="192.168.40.0/24"
VLAN_ADMIN="192.168.30.0/24"
VLAN_SERVERS="192.168.20.0/24"
DMZ_WEBSERVER_IP="192.168.10.10"
AD_SERVER_IP="192.168.20.10"

 0. Réinitialisation
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X

 1. Politiques par défaut
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

 2. Base système
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -m conntrack --ctstate INVALID -j DROP
iptables -A FORWARD -m conntrack --ctstate INVALID -j DROP

 3. Anti-spoofing (bloque IP privées sur WAN)
iptables -A INPUT -i "$WAN_IF" -s 10.0.0.0/8 -j DROP
iptables -A INPUT -i "$WAN_IF" -s 172.16.0.0/12 -j DROP
iptables -A INPUT -i "$WAN_IF" -s 192.168.0.0/16 -j DROP

 4. ICMP (ping limité)
iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 10/second --limit-burst 20 -j ACCEPT
iptables -A FORWARD -p icmp -m limit --limit 10/second --limit-burst 20 -j ACCEPT

 5. NAT (sortie Internet des VLANs internes)
iptables -t nat -A POSTROUTING -o "$WAN_IF" -s "$VLAN_USERS" -j MASQUERADE
iptables -t nat -A POSTROUTING -o "$WAN_IF" -s "$VLAN_ADMIN" -j MASQUERADE
iptables -t nat -A POSTROUTING -o "$WAN_IF" -s "$VLAN_SERVERS" -j MASQUERADE

 6. Sortie Internet depuis VLAN_UTILISATEURS
iptables -A FORWARD -s "$VLAN_USERS" -o "$WAN_IF" -p tcp --dport 80 -j ACCEPT
iptables -A FORWARD -s "$VLAN_USERS" -o "$WAN_IF" -p tcp --dport 443 -j ACCEPT

 7. Accès DMZ Web (HTTP/HTTPS)
iptables -A FORWARD -s "$VLAN_USERS" -d "$DMZ_WEBSERVER_IP" -p tcp --dport 80 -j ACCEPT
iptables -A FORWARD -s "$VLAN_USERS" -d "$DMZ_WEBSERVER_IP" -p tcp --dport 443 -j ACCEPT
iptables -A FORWARD -s "$VLAN_ADMIN" -d "$DMZ_WEBSERVER_IP" -p tcp --dport 443 -j ACCEPT
iptables -A FORWARD -s "$VLAN_SERVERS" -d "$DMZ_WEBSERVER_IP" -p tcp --dport 443 -j ACCEPT
iptables -A FORWARD -i "$WAN_IF" -d "$DMZ_WEBSERVER_IP" -p tcp --dport 443 -j ACCEPT

 8. Administration (SSH, RDP, LDAP, SMB)
iptables -A INPUT -s "$VLAN_ADMIN" -p tcp --dport 22 -j ACCEPT
iptables -A FORWARD -s "$VLAN_ADMIN" -d "$DMZ_WEBSERVER_IP" -p tcp --dport 22 -j ACCEPT
iptables -A FORWARD -s "$VLAN_ADMIN" -d "$AD_SERVER_IP" -p tcp --dport 3389 -j ACCEPT
iptables -A FORWARD -s "$VLAN_ADMIN" -d "$AD_SERVER_IP" -p tcp -m multiport --dports 389,445,135 -j ACCEPT
iptables -A FORWARD -s "$VLAN_ADMIN" -d "$AD_SERVER_IP" -p udp --dport 389 -j ACCEPT

 9. Accès utilisateurs vers AD
iptables -A FORWARD -s "$VLAN_USERS" -d "$AD_SERVER_IP" -p tcp --dport 389 -j ACCEPT
iptables -A FORWARD -s "$VLAN_USERS" -d "$AD_SERVER_IP" -p udp --dport 389 -j ACCEPT
iptables -A FORWARD -s "$VLAN_USERS" -d "$AD_SERVER_IP" -p tcp --dport 445 -j ACCEPT

 10. DNS interne
iptables -A FORWARD -s "$VLAN_USERS" -d "$AD_SERVER_IP" -p udp --dport 53 -j ACCEPT
iptables -A FORWARD -s "$VLAN_ADMIN" -d "$AD_SERVER_IP" -p udp --dport 53 -j ACCEPT

 11. DHCP
iptables -A FORWARD -s "$VLAN_USERS" -p udp --dport 67:68 --sport 67:68 -j ACCEPT
iptables -A FORWARD -s "$VLAN_ADMIN" -p udp --dport 67:68 --sport 67:68 -j ACCEPT

 12. NTP
iptables -A FORWARD -s "$VLAN_USERS" -p udp --dport 123 -j ACCEPT
iptables -A FORWARD -s "$VLAN_ADMIN" -p udp --dport 123 -j ACCEPT
iptables -A FORWARD -s "$VLAN_SERVERS" -p udp --dport 123 -j ACCEPT

 13. Publication DMZ (DNAT HTTPS)
iptables -t nat -A PREROUTING -i "$WAN_IF" -p tcp --dport 443 -j DNAT --to-destination "$DMZ_WEBSERVER_IP":443
iptables -A FORWARD -i "$WAN_IF" -p tcp --dport 443 -d "$DMZ_WEBSERVER_IP" -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT

 14. Blocages inter-VLAN
iptables -A FORWARD -s "$VLAN_USERS" -d "$VLAN_SERVERS" -j DROP
iptables -A FORWARD -s "$VLAN_USERS" -d "$VLAN_ADMIN" -j DROP
iptables -A FORWARD -s "$VLAN_ADMIN" -d "$VLAN_USERS" -j DROP
iptables -A FORWARD -s "$VLAN_SERVERS" -d "$VLAN_USERS" -j DROP

 15. SMTP contrôlé
iptables -A FORWARD -s "$VLAN_SERVERS" -o "$WAN_IF" -p tcp --dport 25 -j ACCEPT
iptables -A FORWARD -s "$VLAN_USERS" -o "$WAN_IF" -p tcp --dport 25 -j DROP
iptables -A FORWARD -s "$VLAN_ADMIN" -o "$WAN_IF" -p tcp --dport 25 -j DROP

 16. Journalisation avec limitation
iptables -A INPUT -m limit --limit 5/second --limit-burst 20 -j LOG --log-prefix "iptables INPUT drop: " --log-level 7
iptables -A FORWARD -m limit --limit 5/second --limit-burst 20 -j LOG --log-prefix "iptables FORWARD drop: " --log-level 7

 17. Sauvegarde des règles
netfilter-persistent save
