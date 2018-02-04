# mysql-transfer
A simple tool for Mysql data transfer, which runs in interactive or batch mode and creates data transfer profiles which can be shared between developers alongside a project.

## USAGE:
`mysql-transfer PATH FORCE`
 - Argument 1 - PATH:  configuration path. eg: ./sample-transfer
 - Argument 2 - FORCE: (optional) "force" - bypass configuration questions and run all data migrations

Examples
- `mysql-transfer ./sample-transfer` Run an interactive data transfer, select source and destination and transfer data
- `mysql-transfer ./sample-transfer force` Run a non-interactive transfer. Previous settings will be reused.

## CONFIG FOLDER STRUCTURE:
 - ./structure-data-tables.dist.txt > one table per line, containing all default tables to dump with data
 - ./structure-only-tables.dist.txt > one table per line, containing all default tables to dump without data
 - ./configuration.dist.sh > configuration file, contains clauses for dumping subsets of tables (eg: most recent data)
 - ./data-updates.dist.sql > SQL queries to run after transfer

## NOTES:
 - The config folder basename must be unique for each transfer, as it is used as a mysql "login path"
 - All files can exist in 2 versions: *.dist.* files  and *.user.* files
   *.user.* files have precedence and are ignored in git
   *.dist.* files can be created from *.user.* files to share a transfer profile across a team
 - mysqldump and mysql_config_editor MUST BE in the path

##### THE SMALL LINES:
Copyright (C) 2018 Webelop Ltd
Contact: Jean-Charles Callu <jc@webelop.net>

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
