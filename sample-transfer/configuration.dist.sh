#!/bin/sh
# Distribute file: configuration.dist.sh
# Customize in:    configuration.user.sh
#
# Variables used in the mysql-transfer can be initialized here

LIMITEDDATA_TABLES=()

# Example with direct limit clause
LIMITEDDATA_TABLES+=("--where='created > NOW() - INTERVAL 1 WEEK' -- tracking")

# Example with placeholder limit clause. Placeholder query is {PLACEHOLDER_NAME}_QUERY
MIN_ORDER_ID_QUERY='SELECT min(id) FROM sales_order WHERE created > NOW() - INTERVAL 1 WEEK'
LIMITEDDATA_TABLES+=("--where='id > {{ MIN_ORDER_ID }}' -- sales_order")
LIMITEDDATA_TABLES+=("--where='sales_order_id > {{ MIN_ORDER_ID }}' -- sales_order_line")
