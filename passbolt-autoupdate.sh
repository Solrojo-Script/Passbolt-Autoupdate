#!/bin/bash

# Script développé par Gabriel GAITAN en 2025
#
# Pas de Copyright, ce script est libre et gratuit :)
#
# Ce script a pour but la mise à jour automatique de passbolt
# Ce script est purement compatible avec bash shell
#
# Notes : Lorsque vous voyez 2>&1, 2 est le descripteur de fichier 2 (erreur standard par défaut)
# >& est un opérateur de redirection qui redirige vers un descripteur de fichier, 
# qui est dans ce cas 1 (sortie standard par défaut ). 


#Setup Colors
purple=$(tput setaf 171)
red=$(tput setaf 1)
green=$(tput setaf 2)
cyan=$(tput setaf 6)
tan=$(tput setaf 3)
bold=$(tput bold)
reset=$(tput sgr0)

#Setup Headers
e_header() { printf "\n${bold}${purple}==========  %s  ==========${reset}\n" "$@";}

e_arrow() { printf "${cyan}➜ $@\n";}

e_success() { printf "${green}✔ %s${reset}\n" "$@";}

e_error() { printf "${red}✖ %s${reset}\n" "$@";}

e_warning() { printf "${tan}⚠ %s${reset}\n" "$@"; }

#init
#

e_header "Mise à jour automatique de passbolt"

stopnginx() {
	e_warning "Stop du service Passbolt..."
	
	output_stop_nginx=$(sudo systemctl stop nginx 2>&1)
	exit_code_stop_nginx=$?

	if [ $exit_code_stop_nginx -eq 0 ];
	then
		sleep 2
		e_success "Le service Passbolt a été arrêté"
		sleep 2
		maj
	else 
		sleep 2
		e_error "Impossible d'arrêter le service Nginx!"
		echo "$output_stop_nginx"
		exit 1
	fi
}

maj() {
	e_arrow "Vérification des mise à jours ..."
	sleep 2

	# Actualisation de la liste des paquets
	output_update=$(sudo apt update 2>&1)
	exit_code_update=$?
	
	if [ $exit_code_update -ne 0 ];
	then
		e_error "Echec de la maj de la liste de paquets"
		echo "$output_update"
		exit 1
	else
		e_success "Vérification OK !"
		sleep 2
		e_arrow "Mise à jour de Passbolt..."

		# Mise à jour de Passbolt
   		output_upgrade_passbolt=$(sudo apt --only-upgrade install passbolt-ce-server 2>&1)
    	exit_code_passbolt=$?

    	# Mise à jour complète du système
    	output_upgrade_all=$(sudo apt upgrade -y 2>&1)
    	exit_code_upgrade_all=$?

    	if [ $exit_code_passbolt -eq 0 ] && [ $exit_code_upgrade_all -eq 0 ]
    	then
    		e_success "Mise à jour Passbolt OK"
			sleep 2
			nettoyer
		else
			e_warning "Des Problèmes ont été détecté"

			sleep 2
			if [ $exit_code_passbolt -eq 1 ] && [ $exit_code_upgrade_all -eq 0 ]
			then
				e_error "Impossible de mettre à jour Passbolt!"
				sleep 1
				echo "$output_upgrade_passbolt"
			elif [ $exit_code_passbolt -eq 0 ] && [ $exit_code_upgrade_all -eq 1 ]
			then 
				e_error "Impossible de mettre à jour les paquets!"
				sleep 1
				echo "$output_upgrade_all"
			fi
			exit 1
		fi
	fi
}

nettoyer() {
	e_arrow "Nettoyage du cache ..."
	sleep 3
	sudo -H -u www-data bash -c "/usr/share/php/passbolt/bin/cake cache clear_all" > /dev/null
	sleep 2
	startnginx
}

startnginx() {
	e_warning "Start du service Passbolt ..."
	
	output_start_nginx=$(sudo systemctl start nginx 2>&1)
	exit_code_start_nginx=$?

	if [ $exit_code_start_nginx -eq 0 ]
	then
		sleep 3
		e_success "Mise à jour Passbolt OK :)"
		exit 0
	else
		e_error "Impossible de démarrer le service Nginx"
		echo "$output_start_nginx"
		exit 1
	fi
}

healthcheck() {
	sleep 2
	
	need_for_update=false
	critical_error=false
	warning=false

	e_arrow "Healthcheck..."

	output_health=$(sudo -H -u www-data bash -c "/usr/share/php/passbolt/bin/cake passbolt healthcheck" 2>&1 )
	
	sleep 2
	
	while IFS= read -r line 
	    do
			if [ "$line" == *"This installation is not up to date."* ]
			then
				need_for_update=true
			
			elif [ "$line" == *"FAIL"* ] && [ "$need_for_update" == false ]
			then
	 			e_warning "Erreur détecté : $line"

	 			critical_error=true

	 			sleep 1
   				
   				if [ "$line" == *"GPG"* ]
    			then
    				e_error "Problème avec le GPG"
    				#corriger_gpg
    
    			elif [ "$line" == *"Database"* ]
    			then
        			e_error "Problème avec la base de données"
        			#verifier_db
    
    			elif [ "$line" == *"Cron"* ]
    			then
        			e_error "Problème avec cron"
        			#relancer_cron
        		else
        			e_error "Échec non reconnu : $line"
    			fi

    			# Sauvegarde la sortie des messages dans le fichier log
    			{
    				echo "====== [$(date '+%Y-%m-%d %H:%M:%S')] Healthcheck ======"
    				echo "$output_health"
    				echo
				} >> /var/log/passbolt/autoupdate.log

   		 	elif [ "$line" == *"WARNING"* ]
    		then
    			warning=true

        		e_warning "Avertissement : $line"

        		# Sauvegarde la sortie des messages dans le fichier log
    			{
    				echo "====== [$(date '+%Y-%m-%d %H:%M:%S')] Healthcheck ======"
    				echo "$output_health"
    				echo
				} >> /var/log/passbolt/autoupdate.log

    		fi

	done <<< "$output_health" # Alimenta el bucle while con el output del comando healthcheck
	
	if [ "$warning" == true ] || [ "$critical_error" == true ]
	then
		sleep 1
    	e_arrow "Voir fichier '/var/log/passbolt/autoupdate.log' pour plus d'information"
    	sleep 2
    	exit 1
    fi

	if [ "$need_for_update" == true ] && [ "$critical_error" == false ]
	then
		e_success "Healthcheck OK !"
		sleep 1
		stopnginx

	elif [ "$need_for_update" == false ] && [ "$critical_error" == false ]
	then
		e_success "Passbolt est déjà à la dernière version"
		exit 0
	fi
}

healthcheck