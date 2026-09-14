# Cost

us-east-1, account `103714492562`. Checked 13 Sep 2026.

Idle cost is about **$0.04 / month** (about **$0.001 / day**). Nothing in this stack has an hourly meter. Bedrock is on-demand, so the bill moves only when something invokes a model or writes logs.

Cost Explorer is not enabled on this account. Figures below are from a resource inventory plus published on-demand rates, not from the invoice. Rates change — confirm on the [Bedrock pricing page](https://aws.amazon.com/bedrock/pricing/) before budgeting.

## Standby

Leaving both Lambdas deployed does not add a daily charge. Enabling Bedrock model access does not either.

| Service | What exists | Standby |
| --- | --- | --- |
| S3 | 1.8 GB across two buckets, versioning on | about $0.04 / month |
| Lambda | `bedrock-inference-prod` and `bedrock-inference-dev`, 2048 MB, no provisioned concurrency | $0 |
| Lambda code storage | 185 MB of the 75 GB free allowance | $0 |
| Function URL | public URL, auth type NONE | $0 |
| Bedrock | on-demand only; no provisioned throughput, no imported models | $0 |
| CloudWatch Logs | two log groups, 0 bytes, never expire | $0 |
| CloudWatch alarms / dashboards | none | $0 |
| KMS | AWS-managed Lambda key only (`alias/aws/lambda`) | $0 |
| VPC | default VPC only; no NAT, no public IPv4, no instances, no volumes | $0 |
| Not present | load balancers, RDS, DynamoDB, SQS, SNS, API Gateway, CloudFront, Route 53, SageMaker, ECR, Secrets Manager, CloudTrail, GuardDuty, Security Hub, Premium Support | $0 |

S3 is the only idle line item. Standard storage in us-east-1 is $0.023 / GB-month.

| Bucket | Current | Old versions | Total |
| --- | ---: | ---: | ---: |
| `bedrock-inference-tfstate-103714492562` | 0.86 GB | 0.69 GB | 1.55 GB |
| `huggingface-bedrock-models-103714492562` | 0.25 GB | 0 | 0.25 GB |

The tfstate bucket is not just state. It holds Lambda zips, and versioning keeps older copies, so that line grows a little on each deploy.

## This month so far

Last 30 days of CloudWatch: Bedrock activity on one day only — 55 invocations, 1,756 input tokens, 1,168 output tokens. That is the smoke run plus a few extra calls, priced at under $0.01. A full `scripts/smoke.sh` (sync + stream, all aliases) is about $0.0006.

| How often the full smoke runs | Bedrock |
| --- | ---: |
| Once | $0.0006 |
| Once a day | $0.02 / month |
| Once an hour | $0.41 / month |

MiniLM is in-process. It does not add a Bedrock charge.

## Model rates

USD per 1 million tokens, us-east-1 on-demand, standard tier. Input / output.

| Alias | Bedrock ID | Input | Output |
| --- | --- | ---: | ---: |
| `gemma-3-4b` | `google.gemma-3-4b-it` | $0.04 | $0.08 |
| `nova-micro` | `amazon.nova-micro-v1:0` | $0.035 | $0.14 |
| `nova-lite` | `amazon.nova-lite-v1:0` | $0.06 | $0.24 |
| `ministral-3b` | `mistral.ministral-3-3b-instruct` | $0.10 | $0.10 |
| `ministral-8b` | `mistral.ministral-3-8b-instruct` | $0.15 | $0.15 |
| `ministral-14b` | `mistral.ministral-3-14b-instruct` | $0.20 | $0.20 |
| `gemma-3-12b` | `google.gemma-3-12b-it` | $0.09 | $0.29 |
| `gemma-3-27b` | `google.gemma-3-27b-it` | $0.23 | $0.38 |
| `gpt-oss-safeguard-20b` | `openai.gpt-oss-safeguard-20b` | $0.07 | $0.20 |
| `gpt-oss` / `gpt-oss-120b` | `openai.gpt-oss-120b-1:0` | $0.15 | $0.60 |
| `gpt-oss-safeguard` / `gpt-oss-safeguard-120b` | `openai.gpt-oss-safeguard-120b` | $0.15 | $0.60 |
| `qwen3-32b` | `qwen.qwen3-32b-v1:0` | $0.15 | $0.60 |
| `qwen3-next-80b-a3b` | `qwen.qwen3-next-80b-a3b` | $0.15 | $1.20 |
| `llama4` / `llama4-maverick` | `us.meta.llama4-maverick-17b-instruct-v1:0` | $0.24 | $0.97 |
| `llama` | `us.meta.llama3-3-70b-instruct-v1:0` | $0.72 | $0.72 |
| `deepseek` | `deepseek.v3.2` | $0.62 | $1.85 |
| `nova-pro` | `amazon.nova-pro-v1:0` | $0.80 | $3.20 |
| `minilm-l12-h384` | in-process | $0 | $0 |

`gpt-oss-20b` is not in the smoke list. Published rate is about $0.07 input / $0.30 output per 1M tokens. Batch is typically half of on-demand. Priority is higher. This stack does not set a service tier, so requests use standard on-demand.

`gpt-oss` and both safeguard models bill reasoning tokens as output. A one-word reply can still be 50–200 completion tokens. The table below does not include that extra.

## Example traffic

1,000 requests / day, 1,000 input tokens + 250 output tokens each. Scale linearly. 10,000 requests / day is 10× the month column.

| Alias | Per 1,000 requests | Per day | Per month (30 days) |
| --- | ---: | ---: | ---: |
| `gemma-3-4b` | $0.06 | $0.06 | $1.80 |
| `nova-micro` | $0.07 | $0.07 | $2.10 |
| `ministral-3b` | $0.13 | $0.13 | $3.75 |
| `ministral-8b` | $0.19 | $0.19 | $5.60 |
| `qwen3-32b` / `gpt-oss` | $0.30 | $0.30 | $9.00 |
| `qwen3-next-80b-a3b` | $0.45 | $0.45 | $13.50 |
| `llama` | $0.90 | $0.90 | $27 |
| `deepseek` | $1.08 | $1.08 | $32 |
| `nova-pro` | $1.60 | $1.60 | $48 |

Formula, with rates in USD per 1M tokens:

```
cost = (input_tokens / 1e6) * input_rate + (output_tokens / 1e6) * output_rate
```

Lambda is small next to those figures. At 2048 MB, a few seconds per call, 1,000 requests / day is a few dollars / month ($0.0000166667 per GB-second, plus $0.20 per 1M requests). It only starts to matter if calls sit near the 60-second timeout, or if provisioned concurrency is added. Do not add provisioned concurrency for standby — that is an hourly charge.

There is no free-tier assumption here. A new account's Lambda free tier (1M requests and 400,000 GB-seconds / month for 12 months) would cover light use if it still applies.
