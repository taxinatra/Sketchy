#!/bin/sh
while true; do
    read -p "WARNING: You are about to deploy the production version! Are you sure? yes/no: " yn
    case $yn in
        yes ) ./deploy 2528h472689461; break;;
        * ) echo "Aborting..."; exit;;
    esac
done

