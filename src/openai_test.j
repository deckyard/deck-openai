# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

/**
 * White-box tests: jennifer test src/openai_test.j
 *
 * No test needs an API key or a model server. A fake on 127.0.0.1
 * (`startFake` in the core overlay) answers each request from a script and
 * records what it got; the answers are replies recorded from OpenAI's API
 * reference and from a live Ollama (`topics/fixtures/replies_test.j`). The
 * topic overlays are fragments spliced in here, not standalone suites.
 */
use httpd;
use net;
use testing;

include "topics/fixtures/replies_test.j";
include "topics/core_test.j";
include "topics/chat_test.j";
include "topics/tools_test.j";
include "topics/embeddings_test.j";
