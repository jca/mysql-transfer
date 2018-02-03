-- File: data-updates.dist.sql
-- SQL commands to execute to adapt destination database after data transfer

REPLACE INTO `config`
  (`name`, `value`)
VALUES
  ('this', 'that'),
  ('these', 'those');

