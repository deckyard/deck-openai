# @deckyard/openai

[![test](https://github.com/deckyard/deck-openai/actions/workflows/test.yml/badge.svg)](https://github.com/deckyard/deck-openai/actions/workflows/test.yml)
[![Documentation](https://img.shields.io/badge/docs-github%20pages-blue)](https://deckyard.github.io/deck-openai/)
[![release](https://img.shields.io/github/v/release/deckyard/deck-openai)](https://github.com/deckyard/deck-openai/releases/latest)

A client for the OpenAI™-compatible API for [Jennifer](https://jennifer-lang.dev/)
programs: Chat Completions with tools and structured output, a tool loop
that runs the model's tool calls through a function, embeddings and model
listing. The base URL is settable, so it talks to OpenAI, Azure™ OpenAI,
Ollama™, vLLM™, the llama.cpp™ server, LM Studio™, OpenRouter™, Groq™, Mistral™
and Together™ alike. Every request has a deadline, a reply cap and retries
on 408, 409, 429, 5xx and a refused connection, never resending a request
the server may have received; errors carry the server's
status, type, code, the wait it asked for and its rate-limit headers.

**[Documentation](https://deckyard.github.io/deck-openai/)**

## Install

```sh
jvc add @deckyard/openai
```

This vendors the deck to `vendor/<scope>/openai/`. Without `jvc`, unpack the
`src/` subtree of a release archive (`<scope>-openai-<version>.tar.gz`) there.

## Usage

```jennifer
import "@deckyard/openai/" as openai;

def c as openai.Client init openai.client(os.getEnv("OPENAI_API_KEY"));
def req as json.Value init openai.newRequest("gpt-5.4-mini");
$req = openai.addUserText($req, "Name three prime numbers.");
io.printf("%s\n", openai.text(openai.chat($c, $req)));
```

A local model through Ollama needs no key:

```jennifer
def local as openai.Client init openai.withBaseUrl(openai.client(""), "http://127.0.0.1:11434/v1");
```

## Requirements

Jennifer 0.28.0 or newer, the default binary: the deck opens sockets
(capability `net`), which `jennifer-tiny` does not have. An API key for a
hosted service, or a local OpenAI-compatible server. No streaming yet.

## Development

```sh
tools/check-all.sh                   # the full gate, as CI runs it
jennifer test src/openai_test.j      # the test overlay (a loopback fake, no key needed)
tools/check-docs.sh                  # docs against the code
tools/pack.sh dist                   # build the release archive
```

## Licence

LGPL-3.0-only, see [LICENSE](LICENSE). Copyright (C) 2026 mplx &lt;mplx@jennifer-lang.dev&gt;.

## Trademarks

OpenAI™ is a trademark of OpenAI Foundation. Azure™ and Microsoft Entra™ are
trademarks of Microsoft Corporation. Gemini™ is a trademark of Google LLC.
Groq™ is a trademark of Groq, Inc. Ollama™ is a trademark of Ollama Inc.
OpenRouter™ is a trademark of OpenRouter, Inc. LM Studio™ is a trademark of
Element Labs Inc. Other product and company names may be trademarks of their
respective owners. They are used only to identify the products this deck
works with. This deck is an independent project, not affiliated with,
sponsored or endorsed by OpenAI Foundation or any other provider named here.
