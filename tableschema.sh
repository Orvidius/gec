#!/bin/bash
mysqldump -u www -p edastro --no-data --skip-add-drop-table > tableschema.txt
