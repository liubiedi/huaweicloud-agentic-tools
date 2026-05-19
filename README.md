# HuaweiCloud Agentic Tools

AI-powered agentic tools for automating Huawei Cloud landing zone deployment and management.

## Overview

This repository provides a collection of intelligent agents and automation utilities designed to streamline the provisioning, configuration, and governance of Huawei Cloud landing zones. It leverages large language models (LLMs) and agentic workflows to reduce manual effort and enforce cloud best practices at scale.

## Features

- [ ] Landing zone scaffolding and account vending
- [ ] Policy-as-code enforcement (IAM, SCPs, tagging)
- [ ] Network topology automation (VPC, subnets, peering)
- [ ] Compliance and security baseline deployment
- [ ] Drift detection and remediation agents
- [ ] Cost governance and resource lifecycle management

## Getting Started

### Prerequisites

- Python 3.10+
- Huawei Cloud credentials configured (`~/.huaweicloud/credentials` or environment variables)
- [Huawei Cloud SDK for Python](https://github.com/huaweicloud/huaweicloud-sdk-python-v3)

### Installation

```bash
git clone https://github.com/liubiedi/huaweicloud-agentic-tools.git
cd huaweicloud-agentic-tools
python -m venv .venv
source .venv/bin/activate  # Windows: .venv\Scripts\activate
pip install -r requirements.txt
```

### Usage

```bash
# Coming soon
```

## Project Structure

```
huaweicloud-agentic-tools/
├── agents/          # Agentic workflow definitions
├── tools/           # Huawei Cloud API wrappers and utilities
├── configs/         # Landing zone configuration templates
├── tests/           # Unit and integration tests
└── docs/            # Architecture and usage documentation
```

## License

MIT License — see [LICENSE](LICENSE) for details.
