#!/bin/bash
su - www -c "cd /www/edastro.com/catalog ; ./broken-images.pl $1 ; cd -"
