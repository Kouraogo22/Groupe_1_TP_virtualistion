#!/bin/bash

# Mise à jour et installation des paquets
apt-get update
apt-get install -y apache2 php libapache2-mod-php php-mysql php-mbstring

# Activation de la configuration PHP
a2enconf php
a2enmod rewrite

# Configuration d'Apache pour traiter les fichiers PHP
cat > /etc/apache2/conf-available/php.conf <<EOF
<FilesMatch \.php$>
    SetHandler application/x-httpd-php
</FilesMatch>
EOF

# Activer la nouvelle configuration et recharger Apache
a2enconf php
systemctl reload apache2

# Créer un fichier de configuration pour les connexions DB sécurisées
mkdir -p /etc/apache2/secure
cat > /etc/apache2/secure/db-config.php << 'EOF'
<?php
// Configuration des bases de données
// Master (écriture)
define('DB_MASTER_HOST', '192.168.56.20');
define('DB_MASTER_USER', 'web_user');
define('DB_MASTER_PASS', 'password');
// Slave (lecture)
define('DB_SLAVE_HOST', '192.168.56.21');
define('DB_SLAVE_USER', 'readonly_user');
define('DB_SLAVE_PASS', 'password');
// Base de données
define('DB_NAME', 'accounts_db');
?>
EOF

# Sécuriser le fichier de configuration
chmod 600 /etc/apache2/secure/db-config.php
chown www-data:www-data /etc/apache2/secure/db-config.php

# Création du fichier de configuration de l'application
cat > /var/www/html/config.php << 'EOF'
<?php
// Démarrer la session
session_start();

// Inclure la configuration de la base de données
require_once('/etc/apache2/secure/db-config.php');

// Fonction de connexion à la base de données Master (écriture)
function connectToMaster() {
    $db = new mysqli(DB_MASTER_HOST, DB_MASTER_USER, DB_MASTER_PASS, DB_NAME);
    if ($db->connect_error) {
        throw new Exception("Erreur connexion Master: " . $db->connect_error);
    }
    if (!$db->set_charset("utf8mb4")) {
        throw new Exception("Erreur encodage MySQL: " . $db->error);
    }
    return $db;
}

// Fonction de connexion à la base de données Slave (lecture)
function connectToSlave() {
    $db = new mysqli(DB_SLAVE_HOST, DB_SLAVE_USER, DB_SLAVE_PASS, DB_NAME);
    if ($db->connect_error) {
        throw new Exception("Erreur connexion Slave: " . $db->connect_error);
    }
    if (!$db->set_charset("utf8mb4")) {
        throw new Exception("Erreur encodage MySQL: " . $db->error);
    }
    return $db;
}

// Fonction pour générer un token CSRF
function generateCSRFToken() {
    if (empty($_SESSION['csrf_token'])) {
        $_SESSION['csrf_token'] = bin2hex(random_bytes(32));
    }
    return $_SESSION['csrf_token'];
}

// Fonction pour vérifier un token CSRF
function verifyCSRFToken($token) {
    if (empty($_SESSION['csrf_token']) || $token !== $_SESSION['csrf_token']) {
        return false;
    }
    return true;
}

// Fonction pour logger les événements
function logEvent($event, $details = '') {
    $logfile = '/var/log/apache2/app_events.log';
    $timestamp = date('Y-m-d H:i:s');
    $ip = $_SERVER['REMOTE_ADDR'] ?? 'CLI';
    $message = "[$timestamp] [$ip] $event: $details\n";
    file_put_contents($logfile, $message, FILE_APPEND);
}
?>
EOF

# Création du fichier index.php
cat > /var/www/html/index.php << 'EOF'
<?php
require_once('config.php');
$csrf_token = generateCSRFToken();
?>
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Création de compte - Serveur <?php echo gethostname(); ?></title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script>
        tailwind.config = {
            theme: {
                extend: {
                    colors: {
                        primary: {
                            50: '#f0fdf4',
                            100: '#dcfce7',
                            200: '#bbf7d0',
                            300: '#86efac',
                            400: '#4ade80',
                            500: '#22c55e', // Vert principal
                            600: '#16a34a',
                            700: '#15803d',
                            800: '#166534',
                            900: '#14532d',
                        },
                        warning: {
                            50: '#fefce8',
                            100: '#fef9c3',
                            200: '#fef08a',
                            300: '#fde047',
                            400: '#facc15', // Jaune principal
                            500: '#eab308',
                            600: '#ca8a04',
                            700: '#a16207',
                            800: '#854d0e',
                            900: '#713f12',
                        },
                        danger: {
                            50: '#fef2f2',
                            100: '#fee2e2',
                            200: '#fecaca',
                            300: '#fca5a5',
                            400: '#f87171',
                            500: '#ef4444', // Rouge principal
                            600: '#dc2626',
                            700: '#b91c1c',
                            800: '#991b1b',
                            900: '#7f1d1d',
                        }
                    }
                }
            }
        }
    </script>
    <style>
        @import url('https://fonts.googleapis.com/css2?family=Poppins:wght@300;400;500;600;700&display=swap');
        body {
            font-family: 'Poppins', sans-serif;
        }
        .animate-bounce-slow {
            animation: bounce 3s infinite;
        }
        @keyframes bounce {
            0%, 100% { transform: translateY(0); }
            50% { transform: translateY(-10px); }
        }
    </style>
</head>
<body class="bg-gradient-to-br from-primary-50 to-gray-50 min-h-screen">
    <!-- Barre de navigation -->
    <nav class="bg-primary-700 shadow-lg">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
            <div class="flex items-center justify-between h-16">
                <div class="flex items-center">
                    <div class="flex-shrink-0 flex items-center">
                        <svg class="h-8 w-8 text-primary-200 animate-bounce-slow" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 11c0 3.517-1.009 6.799-2.753 9.571m-3.44-2.04l.054-.09A13.916 13.916 0 008 11a4 4 0 118 0c0 1.017-.07 2.019-.203 3m-2.118 6.844A21.88 21.88 0 0015.171 17m3.839 1.132c.645-2.266.99-4.659.99-7.132A8 8 0 008 4.07M3 15.364c.64-1.319 1-2.8 1-4.364 0-1.457.39-2.823 1.07-4" />
                        </svg>
                        <span class="ml-2 text-white text-xl font-bold">Account Manager</span>
                    </div>
                </div>
                <div class="text-primary-100">
                    Serveur: <span class="font-mono bg-primary-800 px-2 py-1 rounded"><?php echo gethostname(); ?></span>
                </div>
            </div>
        </div>
    </nav>

    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
        <!-- Notification -->
        <?php if(isset($_GET['status'])): ?>
            <div class="mb-8 rounded-lg px-6 py-4 <?php echo $_GET['status'] === 'success' ? 'bg-primary-100 text-primary-800' : 'bg-danger-100 text-danger-800'; ?>">
                <div class="flex items-center">
                    <?php if($_GET['status'] === 'success'): ?>
                        <svg class="h-6 w-6 mr-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                        </svg>
                    <?php else: ?>
                        <svg class="h-6 w-6 mr-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                        </svg>
                    <?php endif; ?>
                    <span><?php echo htmlspecialchars($_GET['message'] ?? ($_GET['status'] === 'success' ? 'Opération réussie!' : 'Une erreur est survenue')); ?></span>
                </div>
            </div>
        <?php endif; ?>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-12">
            <!-- Formulaire de création -->
            <div class="bg-white rounded-xl shadow-xl overflow-hidden transition-all duration-300 hover:shadow-2xl">
                <div class="bg-gradient-to-r from-primary-600 to-primary-500 p-6">
                    <h2 class="text-white text-2xl font-bold flex items-center">
                        <svg class="h-8 w-8 mr-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M18 9v3m0 0v3m0-3h3m-3 0h-3m-2-5a4 4 0 11-8 0 4 4 0 018 0zM3 20a6 6 0 0112 0v1H3v-1z" />
                        </svg>
                        Création de compte
                    </h2>
                </div>
                <form class="p-6 space-y-6" method="POST" action="/process_form.php">
                    <!-- Token CSRF -->
                    <input type="hidden" name="csrf_token" value="<?php echo $csrf_token; ?>">
                    
                    <div class="space-y-2">
                        <label class="block text-sm font-medium text-gray-700" for="nom">
                            Nom complet
                            <span class="text-danger-500">*</span>
                        </label>
                        <div class="relative">
                            <input class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-primary-500 focus:ring focus:ring-primary-200 focus:ring-opacity-50 py-3 px-4 border" 
                                id="nom" name="nom" type="text" placeholder="Jean Dupont" required>
                            <div class="absolute inset-y-0 right-0 flex items-center pr-3 pointer-events-none">
                                <svg class="h-5 w-5 text-primary-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
                                </svg>
                            </div>
                        </div>
                    </div>

                    <div class="space-y-2">
                        <label class="block text-sm font-medium text-gray-700" for="email">
                            Adresse email
                            <span class="text-danger-500">*</span>
                        </label>
                        <div class="relative">
                            <input class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-primary-500 focus:ring focus:ring-primary-200 focus:ring-opacity-50 py-3 px-4 border" 
                                id="email" name="email" type="email" placeholder="jean.dupont@exemple.com" required>
                            <div class="absolute inset-y-0 right-0 flex items-center pr-3 pointer-events-none">
                                <svg class="h-5 w-5 text-primary-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
                                </svg>
                            </div>
                        </div>
                    </div>

                    <div class="space-y-2">
                        <label class="block text-sm font-medium text-gray-700" for="password">
                            Mot de passe
                            <span class="text-danger-500">*</span>
                        </label>
                        <div class="relative">
                            <input class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-primary-500 focus:ring focus:ring-primary-200 focus:ring-opacity-50 py-3 px-4 border" 
                                id="password" name="password" type="password" placeholder="••••••••" required minlength="8">
                            <div class="absolute inset-y-0 right-0 flex items-center pr-3 pointer-events-none">
                                <svg class="h-5 w-5 text-primary-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
                                </svg>
                            </div>
                        </div>
                        <p class="text-xs text-gray-500">Minimum 8 caractères</p>
                    </div>

                    <div class="flex items-center justify-between">
                        <button type="submit" class="group relative w-full flex justify-center py-3 px-6 border border-transparent text-sm font-medium rounded-md text-white bg-gradient-to-r from-primary-600 to-primary-500 hover:from-primary-700 hover:to-primary-600 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-primary-500 shadow-lg transform transition hover:scale-105 duration-200">
                            <span class="absolute left-0 inset-y-0 flex items-center pl-3">
                                <svg class="h-5 w-5 text-primary-200 group-hover:text-primary-100" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
                                </svg>
                            </span>
                            Créer le compte
                        </button>
                    </div>
                </form>
            </div>

            <!-- Liste des comptes -->
            <div class="bg-white rounded-xl shadow-xl overflow-hidden transition-all duration-300 hover:shadow-2xl">
                <div class="bg-gradient-to-r from-primary-600 to-primary-500 p-6">
                    <h2 class="text-white text-2xl font-bold flex items-center">
                        <svg class="h-8 w-8 mr-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2" />
                        </svg>
                        Liste des comptes
                    </h2>
                    <p class="text-primary-100 text-sm mt-1">
                        Données lues depuis: <span class="font-mono bg-primary-700 px-2 py-1 rounded">db-slave (<?php echo DB_SLAVE_HOST; ?>)</span>
                    </p>
                </div>
                <div class="p-6">
                    <?php include 'fetch_accounts.php'; ?>
                </div>
            </div>
        </div>
    </div>

    <footer class="bg-primary-800 text-white py-8 mt-12">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
            <div class="flex flex-col md:flex-row justify-between items-center">
                <div class="flex items-center space-x-2">
                    <svg class="h-6 w-6 text-primary-300" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z" />
                    </svg>
                    <span class="text-lg font-semibold">Account Manager Pro</span>
                </div>
                <div class="mt-4 md:mt-0 text-center md:text-right">
                    <p class="text-primary-300 text-sm">Serveur: <?php echo gethostname(); ?></p>
                    <p class="text-primary-200 text-xs mt-1">© 2025 Tous droits réservés</p>
                </div>
            </div>
        </div>
    </footer>
    <?php if (isset($_GET['status']) && isset($_GET['message'])): ?>
        <?php 
        $alertClass = ($_GET['status'] == 'success') ? 'alert-success' : 'alert-danger';
        $messageId = ($_GET['status'] == 'success') ? 'success-message' : 'error-message';
        ?>
        
        <div id="<?php echo $messageId; ?>" class="alert <?php echo $alertClass; ?>" role="alert">
            <?php echo htmlspecialchars($_GET['message']); ?>
        </div>

        <script>
            // Faire disparaître le message après 3 secondes
            setTimeout(function() {
                var messageElement = document.getElementById('<?php echo $messageId; ?>');
                if (messageElement) {
                    // Option 1: Cacher l'élément
                    messageElement.style.display = 'none';
                    
                    // OU Option 2: Faire un fondu
                    // messageElement.style.transition = 'opacity 1s';
                    // messageElement.style.opacity = '0';
                    
                    // OU Option 3: Supprimer complètement l'élément du DOM
                    // messageElement.parentNode.removeChild(messageElement);
                }
            }, 3000); // 3000 millisecondes = 3 secondes
        </script>
    <?php endif; ?>
</body>
</html>
EOF

# Création du fichier process_form.php
cat > /var/www/html/process_form.php << 'EOF'
<?php
// Inclusion du fichier de configuration
require_once('config.php');

// Étape 1 - Forcer l'encodage UTF-8
header('Content-Type: text/html; charset=UTF-8');
ini_set('default_charset', 'UTF-8');
mb_internal_encoding('UTF-8');

// Vérification du jeton CSRF


// Étape 2 - Validation
$errors = [];
$required = ['nom', 'email', 'password'];

foreach ($required as $field) {
    if (empty($_POST[$field])) {
        $errors[] = "Le champ $field est obligatoire";
    }
}

if (!empty($_POST['email']) && !filter_var($_POST['email'], FILTER_VALIDATE_EMAIL)) {
    $errors[] = "L'adresse email n'est pas valide";
}

if (!empty($_POST['password']) && strlen($_POST['password']) < 8) {
    $errors[] = "Le mot de passe doit contenir au moins 8 caractères";
}

if ($errors) {
    logEvent('VALIDATION_ERROR', implode('; ', $errors));
    header("Location: index.php?status=error&message=".urlencode(implode("; ", $errors)));
    exit;
}

try {
    // Étape 3 - Connexion à la base de données master (écriture)
    $db_master = connectToMaster();
    
    // Étape 4 - Nettoyage et préparation des données
    $nom = mb_convert_encoding(trim($_POST['nom']), 'UTF-8', 'auto');
    $email = mb_convert_encoding(trim($_POST['email']), 'UTF-8', 'auto');
    $password = password_hash($_POST['password'], PASSWORD_DEFAULT);

    // Étape 5 - Vérification si l'email existe déjà
    $check_stmt = $db_master->prepare("SELECT id FROM accounts WHERE email = ?");
    $check_stmt->bind_param("s", $email);
    $check_stmt->execute();
    $result = $check_stmt->get_result();
    
    if ($result->num_rows > 0) {
        $check_stmt->close();
        $db_master->close();
        logEvent('DUPLICATE_EMAIL', "Email déjà utilisé: $email");
        header("Location: index.php?status=error&message=".urlencode("Cette adresse email est déjà utilisée"));
        exit;
    }
    $check_stmt->close();

    // Étape 6 - Requête préparée pour l'insertion
    $stmt = $db_master->prepare("INSERT INTO accounts (nom, email, password) VALUES (?, ?, ?)");
    if (!$stmt) {
        throw new Exception("Erreur de préparation: ".$db_master->error);
    }

    $stmt->bind_param("sss", $nom, $email, $password);

    // Étape 7 - Exécution
if ($stmt->execute()) {
    logEvent('ACCOUNT_CREATED', "Compte créé pour $email");
    header("Location: index.php?status=success&message=".urlencode("Compte créé avec succès"));
} else {
    throw new Exception($stmt->error);
}
$stmt->close();
$db_master->close();
    
} catch (Exception $e) {
    logEvent('ERROR', $e->getMessage());
    header("Location: index.php?status=error&message=".urlencode("Une erreur est survenue: " . $e->getMessage()));
    exit;
}
?>
EOF

# Création du fichier fetch_accounts.php
cat > /var/www/html/fetch_accounts.php << 'EOF'
<?php
// Inclusion du fichier de configuration
require_once('config.php');

try {
    // Connexion à la base de données SLAVE pour la lecture
    $db_slave = connectToSlave();

    // Exécution de la requête
    $sql = "SELECT id, nom, email, created_at FROM accounts ORDER BY created_at DESC";
    $result = $db_slave->query($sql);

    if ($result->num_rows > 0) {
        echo '<div class="overflow-x-auto">
                <table class="min-w-full divide-y divide-gray-200">
                    <thead class="bg-gray-50">
                        <tr>
                            <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">ID</th>
                            <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Nom</th>
                            <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Email</th>
                            <th scope="col" class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Date de création</th>
                        </tr>
                    </thead>
                    <tbody class="bg-white divide-y divide-gray-200">';
        
        while ($row = $result->fetch_assoc()) {
            echo "<tr>
                    <td class='px-6 py-4 whitespace-nowrap text-sm text-gray-900'>" . htmlspecialchars($row['id']) . "</td>
                    <td class='px-6 py-4 whitespace-nowrap text-sm text-gray-900'>" . htmlspecialchars($row['nom']) . "</td>
                    <td class='px-6 py-4 whitespace-nowrap text-sm text-gray-900'>" . htmlspecialchars($row['email']) . "</td>
                    <td class='px-6 py-4 whitespace-nowrap text-sm text-gray-500'>" . htmlspecialchars($row['created_at']) . "</td>
                  </tr>";
        }

        echo '</tbody></table></div>';
    } else {
        echo '<div class="text-center py-8">
                <svg class="h-16 w-16 text-gray-300 mx-auto" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1" d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2" />
                </svg>
                <p class="mt-4 text-gray-500">Aucun compte trouvé dans la base de données.</p>
              </div>';
    }

    // Fermer la connexion
    $db_slave->close();
    
} catch (Exception $e) {
    echo '<div class="bg-danger-100 border-l-4 border-danger-500 text-danger-700 p-4 mb-6" role="alert">
            <div class="flex items-center"> 
                <svg class="h-5 w-5 mr-2" fill="none" viewBox="0 0 24 24" stroke="currentColor"> 
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.5 15h-3l-2.732 4c-.77 1.333.192 3 1.732 3z" />
                </svg>
                <strong>Erreur :</strong> ' . htmlspecialchars($e->getMessage()) . '
            </div>
          </div>';
    logEvent('DB_ERROR', $e->getMessage());
}
?>
EOF

# Création d'un répertoire pour les logs d'application
mkdir -p /var/log/apache2
touch /var/log/apache2/app_events.log
chown www-data:www-data /var/log/apache2/app_events.log
chmod 644 /var/log/apache2/app_events.log

# Configuration des permissions
chmod 644 /var/www/html/*.php
chown -R www-data:www-data /var/www/html

# Création d'un test PHP
echo "<?php phpinfo(); ?>" > /var/www/html/test.php

# Activation d'Apache
systemctl enable apache2
systemctl restart apache2

echo "Configuration du serveur web terminée avec succès!"
echo "Accédez à l'application via http://192.168.56.10/"