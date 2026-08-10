FROM python:3.11-slim

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

# Install system dependencies (needed for psycopg2)
RUN apt-get update \
    && apt-get install -y --no-install-recommends gcc libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Install python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# The API does not need root privileges at runtime.
RUN useradd --create-home --uid 10001 cleave
USER cleave

# Expose port
EXPOSE 8000

# Run the application using the PORT environment variable (Cloud Run defaults to 8080)
CMD uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}
