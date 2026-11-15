# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0
# pragma-jennifer-capability: net

/**
 * A client for the OpenAI-compatible API: Chat Completions with tools and
 * structured output, a tool loop that runs the model's tool calls through
 * a function, embeddings, model listing, and `call` for any other
 * endpoint. The base URL is settable, so the same client talks to OpenAI,
 * Azure OpenAI, and the servers that implement the API: Ollama, vLLM, the
 * llama.cpp server, LM Studio, OpenRouter, Groq, Mistral, Together.
 *
 * Requests and replies are `json.Value` documents in the API's own field
 * names; helpers build the common parts and read the reply. No streaming:
 * a reply arrives whole.
 *
 * Every request has a deadline and a reply cap, and is retried on 408,
 * 409, 429, 5xx and a network failure before the request was sent, honouring
 * `retry-after-ms` and `retry-after`; a reply cut off mid-way is never
 * retried. Plain `http` is refused except to this machine unless allowed.
 * A request the server refused, and every other failure of this deck,
 * throws `OpenaiError` (kind `"openai"`) with the HTTP `status`, the
 * error's `type`, `code` and `param`, the `x-request-id`, the wait the
 * server asked for and its rate-limit headers; a reply over the cap is kind `"limit"`,
 * a deadline that passed kind `"timeout"`, a connection the server closed
 * mid-reply kind `"closed"`, a network failure kind `"net"` (a
 * `net.NetError`, passed on as it is). No message carries the API key.
 *
 * | topic | covers |
 * | --- | --- |
 * | `core` | `Client`, settings, Azure, the exchange with retries, errors, `models`, `call` |
 * | `chat` | `chat`, request builders, reply readers |
 * | `tools` | `runTools`, `runToolsWith`: the tool loop |
 * | `embeddings` | `embeddings`, `embed`, `vectors` |
 *
 * @module openai
 * @see https://platform.openai.com/docs/api-reference/chat
 * @example
 *   def c as openai.Client init openai.client(os.getEnv("OPENAI_API_KEY"));
 *   def req as json.Value init openai.newRequest("gpt-5.4-mini");
 *   $req = openai.addMessage($req, "user", "Say hello.");
 *   io.printf("%s\n", openai.text(openai.chat($c, $req)));
 */
use binary;
use convert;
use encoding;
use io;
use json;
use lists;
use maps;
use net;
use regex;
use strings;
use task;
use time;

import "http.j" as http;

include "topics/core.j";
include "topics/chat.j";
include "topics/tools.j";
include "topics/embeddings.j";
