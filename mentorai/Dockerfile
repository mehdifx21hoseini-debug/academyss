FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1
WORKDIR /app

COPY pyproject.toml ./
COPY src ./src
RUN pip install --no-cache-dir .

# غیر روت. اگر فرایند به خطر بیفتد، دسترسی ریشه نداشته باشد.
RUN useradd --create-home --uid 10001 mentorai
USER mentorai

CMD ["mentorai", "run-gateway"]
