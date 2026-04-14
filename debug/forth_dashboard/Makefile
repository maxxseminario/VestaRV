.PHONY: help run start stop kill restart clean logs

# Default target
help:
	@echo "Myshkin MCU Configuration Interface - Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  make run       - Start the web application"
	@echo "  make start     - Same as run"
	@echo "  make stop      - Stop any running instances"
	@echo "  make kill      - Force kill any processes on port 8050"
	@echo "  make restart   - Stop and restart the application"
	@echo "  make clean     - Remove log files and Python cache"
	@echo "  make logs      - Show recent command logs"
	@echo ""

# Start the application
run: stop
	@echo "Starting Myshkin MCU Configuration Interface..."
	@echo "Open your browser to: http://localhost:8050"
	@python3 index.py

start: run

# Stop the application gracefully
stop:
	@echo "Stopping any running instances..."
	@lsof -ti:8050 2>/dev/null | xargs -r kill 2>/dev/null || true
	@sleep 1

# Force kill any processes on port 8050
kill:
	@echo "Force killing processes on port 8050..."
	@lsof -ti:8050 2>/dev/null | xargs -r kill -9 2>/dev/null || true

# Restart the application
restart: stop run

# Clean up log files and cache
clean:
	@echo "Cleaning up..."
	@rm -f myshkin_commands.log
	@rm -rf __pycache__
	@rm -f *.pyc
	@find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	@echo "Cleanup complete"

# Show recent logs
logs:
	@if [ -f myshkin_commands.log ]; then \
		echo "Recent command logs:"; \
		tail -n 50 myshkin_commands.log; \
	else \
		echo "No log file found"; \
	fi
