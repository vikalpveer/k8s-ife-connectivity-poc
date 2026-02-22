FROM alpine:3.19

# Install iproute2 for tc command
RUN apk add --no-cache iproute2 bash

WORKDIR /app

# Copy shaping script
COPY shaper.sh .
RUN chmod +x shaper.sh

# Run as root (required for tc commands)
CMD ["./shaper.sh"]
