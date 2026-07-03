# The cardinal-agent image: what a card's worker agent runs inside when
# CARDINAL_WORKSPACE=container (cardinal.md §13). Build with:
#   docker build -t cardinal-agent docker/agent
FROM node:22-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      git ca-certificates curl ripgrep \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g @anthropic-ai/claude-code

RUN useradd -m agent
USER agent
WORKDIR /workspace/repo

# Auth comes from ANTHROPIC_API_KEY injected at `docker run` by the runner.
ENTRYPOINT []
