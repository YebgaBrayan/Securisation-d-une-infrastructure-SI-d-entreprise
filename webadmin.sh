!/bin/bash
 Script de sécurisation du serveur web en DMZ
 Création utilisateur, durcissement Apache et configuration SSH (Mise à jours)
 Variables
ADMIN_IP="192.168.1.10"    IP de ton poste d'administration (VLAN Admin)
SSH_CONFIG="/etc/ssh/sshd_config"
DOMAIN_NAME="mondomaine.local"   Nom de domaine réel de ton projet

 1. Création d’un utilisateur restreint pour l’administration web
echo "Création de l'utilisateur 'webadmin'..."
if ! id "webadmin" &>/dev/null; then
    useradd -m -s /bin/bash webadmin
    echo "Veuillez définir un mot de passe pour l'utilisateur webadmin :"
    passwd webadmin

     Ajout au groupe sudo si nécessaire (administration contrôlée)
    usermod -aG sudo webadmin
    echo "Utilisateur 'webadmin' créé et ajouté au groupe sudo."
else
    echo "L'utilisateur 'webadmin' existe déjà."
fi

 2. Sécurisation des droits sur le répertoire web
echo "Sécurisation des droits sur le répertoire /var/www/html..."
if [ -d "/var/www/html" ]; then
    chown -R webadmin:www-data /var/www/html
    chmod -R 750 /var/www/html
    echo "Droits sécurisés pour /var/www/html."
else
    echo "Le répertoire /var/www/html n'existe pas."
    exit 1
fi

 3. Durcissement d'Apache
echo "Durcissement de la configuration d'Apache..."

 Désactivation du Directory Listing
if ! grep -q "<Directory /var/www/html>" /etc/apache2/apache2.conf; then
    echo '<Directory /var/www/html>
    Options -Indexes
</Directory>' >> /etc/apache2/apache2.conf
    echo "Directory Listing désactivé."
fi

 Suppression des informations de version dans les pages d’erreur
if ! grep -q "ServerSignature Off" /etc/apache2/conf-enabled/security.conf; then
    echo 'ServerSignature Off
ServerTokens Prod' >> /etc/apache2/conf-enabled/security.conf
    echo "Informations de version supprimées des pages d'erreur."
fi

 Forçage HTTPS (redirection HTTP -> HTTPS)
a2enmod rewrite
if ! grep -q "Redirect permanent / https://$DOMAIN_NAME/" /etc/apache2/sites-available/000-default.conf; then
    cat <<EOT >> /etc/apache2/sites-available/000-default.conf
<VirtualHost *:80>
    ServerName $DOMAIN_NAME
    Redirect permanent / https://$DOMAIN_NAME/
</VirtualHost>
EOT
    echo "Redirection HTTP vers HTTPS configurée."
fi

 4. Redémarrage du service Apache
echo "Redémarrage du service Apache..."
systemctl restart apache2
echo "Service Apache redémarré avec succès."

 5. Journalisation et supervision
echo "Activation des logs détaillés d'Apache..."
if ! grep -q "LogLevel warn" /etc/apache2/apache2.conf; then
    echo 'LogLevel warn' >> /etc/apache2/apache2.conf
    systemctl reload apache2
    echo "Journalisation activée."
fi

 6. Configuration SSH
echo "Configuration sécurisée de SSH..."

 Authentification uniquement par clé publique
if ! grep -q "^PubkeyAuthentication yes" $SSH_CONFIG; then
    echo "PubkeyAuthentication yes" >> $SSH_CONFIG
fi
if grep -q "^PasswordAuthentication yes" $SSH_CONFIG; then
    sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' $SSH_CONFIG
fi
if ! grep -q "^PermitRootLogin no" $SSH_CONFIG; then
    echo "PermitRootLogin no" >> $SSH_CONFIG
fi

 Limitation des connexions SSH à webadmin depuis l'IP d'administration
if ! grep -q "AllowUsers webadmin@$ADMIN_IP" $SSH_CONFIG; then
    echo "AllowUsers webadmin@$ADMIN_IP" >> $SSH_CONFIG
fi

 7. Configuration du pare-feu interne pour SSH
if command -v ufw &>/dev/null; then
    echo "Configuration du pare-feu pour autoriser le trafic SSH..."
    ufw allow from $ADMIN_IP to any port 22
else
    echo "UFW n'est pas installé. Installation de UFW..."
    apt install ufw -y
    ufw allow from $ADMIN_IP to any port 22
fi

 Activer le pare-feu si ce n'est pas déjà fait
if ! ufw status | grep -q "active"; then
    ufw enable
fi

 8. Redémarrage du service SSH
echo "Redémarrage du service SSH..."
systemctl restart sshd
echo "Le service SSH a été redémarré avec succès."

 Final Message
echo "Configuration terminée avec succès."
