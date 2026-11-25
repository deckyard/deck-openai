# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# openai - recorded replies for the overlays: from OpenAI's API reference
# (the openai-openapi spec, 2026-11-14) and from a live Ollama 0.40.16 with
# qwen2.5:0.5b and all-minilm. A ' in a recorded text is written \u0027.
# Spliced into openai_test.j via include.

# The default reply of OpenAI's API reference (Create chat completion).
def const CHAT_DOCS as string init '{"id": "chatcmpl-B9MBs8CjcvOU2jLn4n570S5qMJKcT", "object": "chat.completion", "created": 1741569952, "model": "gpt-6-astra", "choices": [{"index": 0, "message": {"role": "assistant", "content": "Hello! How can I assist you today?", "refusal": null, "annotations": []}, "logprobs": null, "finish_reason": "stop"}], "usage": {"prompt_tokens": 19, "completion_tokens": 10, "total_tokens": 29, "prompt_tokens_details": {"cached_tokens": 0, "audio_tokens": 0}, "completion_tokens_details": {"reasoning_tokens": 0, "audio_tokens": 0, "accepted_prediction_tokens": 0, "rejected_prediction_tokens": 0}}, "service_tier": "default"}';

# A function call, from OpenAI's API reference (example Functions): content null, arguments a JSON string with newlines.
def const TOOLS_DOCS as string init '{"id": "chatcmpl-abc123", "object": "chat.completion", "created": 1699896916, "model": "gpt-6-astra", "choices": [{"index": 0, "message": {"role": "assistant", "content": null, "tool_calls": [{"id": "call_abc123", "type": "function", "function": {"name": "get_current_weather", "arguments": "{\n\"location\": \"Boston, MA\"\n}"}}]}, "logprobs": null, "finish_reason": "tool_calls"}], "usage": {"prompt_tokens": 82, "completion_tokens": 17, "total_tokens": 99, "completion_tokens_details": {"reasoning_tokens": 0, "accepted_prediction_tokens": 0, "rejected_prediction_tokens": 0}}}';

# A chat reply of Ollama 0.40.16 with qwen2.5:0.5b, recorded live.
def const CHAT_OLLAMA as string init '{"id":"chatcmpl-569","object":"chat.completion","created":1794694210,"model":"qwen2.5:0.5b","system_fingerprint":"fp_ollama","choices":[{"index":0,"message":{"role":"assistant","content":"The capital of France is Paris."},"finish_reason":"stop"}],"usage":{"prompt_tokens":36,"prompt_tokens_details":{"cached_tokens":0},"completion_tokens":8,"total_tokens":44}}';

# Two parallel tool calls from Ollama 0.40.16 with qwen2.5:0.5b, recorded live: content "", each call with an `index`.
def const TOOLS_OLLAMA as string init '{"id":"chatcmpl-743","object":"chat.completion","created":1794694221,"model":"qwen2.5:0.5b","system_fingerprint":"fp_ollama","choices":[{"index":0,"message":{"role":"assistant","content":"","tool_calls":[{"id":"call_zib463ui","index":0,"type":"function","function":{"name":"get_weather","arguments":"{\"city\":\"Paris\"}"}},{"id":"call_gdzrooo1","index":1,"type":"function","function":{"name":"get_weather","arguments":"{\"city\":\"Berlin\"}"}}]},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":160,"prompt_tokens_details":{"cached_tokens":18},"completion_tokens":40,"total_tokens":200}}';

# The answer after the tool results of TOOLS_OLLAMA, recorded live.
def const TOOLS_OLLAMA_DONE as string init '{"id":"chatcmpl-968","object":"chat.completion","created":1794694538,"model":"qwen2.5:0.5b","system_fingerprint":"fp_ollama","choices":[{"index":0,"message":{"role":"assistant","content":"The weather in Paris is currently at 18°C with a cloudy sky. In Berlin, it\u0027s at 11°C with a rainy sky."},"finish_reason":"stop"}],"usage":{"prompt_tokens":255,"prompt_tokens_details":{"cached_tokens":240},"completion_tokens":32,"total_tokens":287}}';

# Structured output (json_schema, strict) from Ollama 0.40.16, recorded live.
def const SCHEMA_OLLAMA as string init '{"id":"chatcmpl-524","object":"chat.completion","created":1794694224,"model":"qwen2.5:0.5b","system_fingerprint":"fp_ollama","choices":[{"index":0,"message":{"role":"assistant","content":"{\"country\":\"France\",\"capital\":\"Paris\"}"},"finish_reason":"stop"}],"usage":{"prompt_tokens":35,"prompt_tokens_details":{"cached_tokens":24},"completion_tokens":10,"total_tokens":45}}';

# GET /v1/models of Ollama 0.40.16, recorded live.
def const MODELS_OLLAMA as string init '{"object":"list","data":[{"id":"all-minilm:latest","object":"model","created":1794694200,"owned_by":"library"},{"id":"qwen2.5:0.5b","object":"model","created":1794694197,"owned_by":"library"}]}';

# An embedding of "hello" by all-minilm (384 floats) with encoding_format base64, from Ollama 0.40.16, recorded live.
def const EMBED64_OLLAMA as string init '{"object":"list","data":[{"object":"embedding","embedding":"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","index":0}],"model":"all-minilm","usage":{"prompt_tokens":3,"total_tokens":3}}';

# Ollama's answer to an unknown model, recorded live (status 404).
def const ERROR_OLLAMA as string init '{"error":{"message":"model \u0027nope\u0027 not found","type":"not_found_error","param":null,"code":null}}';

# A refusal, in the shape of OpenAI's structured outputs guide: content null,
# refusal set.
def const REFUSAL as string init '{"id": "chatcmpl-r1", "object": "chat.completion", "created": 1741569952, "model": "gpt-6-astra", "choices": [{"index": 0, "message": {"role": "assistant", "content": null, "refusal": "I am sorry, I cannot assist with that request.", "annotations": []}, "logprobs": null, "finish_reason": "stop"}], "usage": {"prompt_tokens": 40, "completion_tokens": 11, "total_tokens": 51}}';

# A reasoning model's reply with cached prompt tokens and reasoning tokens,
# in CompletionUsage's fields.
def const REASONING as string init '{"id": "chatcmpl-o1", "object": "chat.completion", "created": 1741569952, "model": "o3", "choices": [{"index": 0, "message": {"role": "assistant", "content": "42", "refusal": null, "annotations": []}, "logprobs": null, "finish_reason": "stop"}], "usage": {"prompt_tokens": 1500, "completion_tokens": 900, "total_tokens": 2400, "prompt_tokens_details": {"cached_tokens": 1280, "audio_tokens": 0}, "completion_tokens_details": {"reasoning_tokens": 832, "audio_tokens": 0, "accepted_prediction_tokens": 0, "rejected_prediction_tokens": 0}}}';

# A reply cut off at the token limit.
def const TRUNCATED as string init '{"id": "chatcmpl-t1", "object": "chat.completion", "created": 1741569952, "model": "gpt-6-astra", "choices": [{"index": 0, "message": {"role": "assistant", "content": "{\"country\": \"Fra", "refusal": null}, "logprobs": null, "finish_reason": "length"}]}';

# Content as a list of parts, as Mistral sends it for some models.
def const PARTS as string init '{"id": "p1", "object": "chat.completion", "created": 1, "model": "magistral-small", "choices": [{"index": 0, "message": {"role": "assistant", "content": [{"type": "thinking", "thinking": [{"type": "text", "text": "hm"}]}, {"type": "text", "text": "Hello"}, {"type": "text", "text": ", world"}]}, "finish_reason": "stop"}]}';

# A custom tool call (ChatCompletionMessageCustomToolCall) and a function call
# whose arguments are malformed.
def const CUSTOM_AND_BAD as string init '{"id": "c1", "object": "chat.completion", "created": 1, "model": "gpt-6-astra", "choices": [{"index": 0, "message": {"role": "assistant", "content": null, "tool_calls": [{"id": "call_c1", "type": "custom", "custom": {"name": "sql", "input": "SELECT 1"}}, {"id": "call_b1", "type": "function", "function": {"name": "get_weather", "arguments": "{\"city\": \"Rome\""}}]}, "finish_reason": "tool_calls"}]}';

# A reply without choices.
def const NO_CHOICES as string init '{"id": "x", "object": "chat.completion", "created": 1, "model": "m", "choices": []}';

# The embeddings reply of OpenAI's API reference, its vector cut short.
def const EMBED_DOCS as string init '{"object": "list", "data": [{"object": "embedding", "embedding": [0.0023064255, -0.009327292, -0.0028842222], "index": 0}], "model": "text-embedding-3-small", "usage": {"prompt_tokens": 8, "total_tokens": 8}}';

# Two embeddings out of order, as a server may send them.
def const EMBED_SWAPPED as string init '{"object": "list", "data": [{"object": "embedding", "embedding": [2.0, 2.5], "index": 1}, {"object": "embedding", "embedding": [1, 1.5], "index": 0}], "model": "m", "usage": {"prompt_tokens": 2, "total_tokens": 2}}';

# OpenAI's 401 for a wrong key (the error object of the API reference); the
# message masks the key.
def const ERROR_KEY as string init '{"error": {"message": "Incorrect API key provided: sk-proj-****abcd. You can find your API key at https://platform.openai.com/account/api-keys.", "type": "invalid_request_error", "param": null, "code": "invalid_api_key"}}';

# OpenAI's 429 for a rate limit.
def const ERROR_RATE as string init '{"error": {"message": "Rate limit reached for gpt-6-astra on requests per min (RPM): Limit 3, Used 3, Requested 1.", "type": "requests", "param": null, "code": "rate_limit_exceeded"}}';

# OpenAI's 429 for a used-up quota, which a retry does not help.
def const ERROR_QUOTA as string init '{"error": {"message": "You exceeded your current quota, please check your plan and billing details.", "type": "insufficient_quota", "param": null, "code": "insufficient_quota"}}';

# OpenAI's 400 naming the field it is about.
def const ERROR_PARAM as string init '{"error": {"message": "Unsupported parameter: max_tokens is not supported with this model. Use max_completion_tokens instead.", "type": "invalid_request_error", "param": "max_tokens", "code": "unsupported_parameter"}}';

# The llama.cpp server: code a number.
def const ERROR_LLAMA as string init '{"error": {"code": 400, "message": "the request exceeds the available context size", "type": "exceed_context_size_error"}}';

# vLLM before 0.10: the error fields at the top level.
def const ERROR_VLLM as string init '{"object": "error", "message": "The model does not exist.", "type": "NotFoundError", "param": null, "code": 404}';

# Azure OpenAI: a code without a type.
def const ERROR_AZURE as string init '{"error": {"code": "DeploymentNotFound", "message": "The API deployment for this resource does not exist."}}';
