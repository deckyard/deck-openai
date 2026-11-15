# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# openai - white-box tests for the core topic, and the fake server the other
# overlays use. Spliced into openai_test.j via include.

# a key for the fake: never a real one
def const KEY as string init "sk-test-0123456789abcdef";

# the headers the fake records
def const RECORDED as list of string init [
    "Content-Type",
    "Authorization",
    "api-key",
    "OpenAI-Organization",
    "OpenAI-Project",
    "X-Title"
];

/**
 * A running fake OpenAI-compatible server.
 *
 * @field srv {httpd.Server} the server
 * @field base {string} its base URL, with `/v1`
 * @field t {task of list of string} the task serving it; its result is every request seen
 */
def struct Fake {
    srv as httpd.Server,
    base as string,
    t as task of list of string
};

/**
 * Mark a call that should have thrown.
 *
 * @param what {string} what got through
 * @throws {Error} always, kind "missed"
 */
func missed(what as string) {
    throw Error{kind: "missed", message: $what};
}

/**
 * Start a fake server. An answer is looked up by `METHOD path?query#n` (the
 * n-th time that request comes, from 1), then `METHOD path?query`, then
 * `METHOD path`; it is the status, a newline, header lines `Name: value`,
 * an empty line and the body. A request with no answer gets 404 and
 * OpenAI's error object; an answer whose status is `SLEEP` waits 1.5 seconds.
 *
 * @param answers {map of string to string} the answers
 * @return {Fake} the server
 */
func startFake(answers as map of string to string) {
    def srv as httpd.Server init httpd.listen("127.0.0.1:0");
    def base as string init "http://" + httpd.address($srv) + "/v1";
    def t as task of list of string init spawn {
        return serveFake($srv, $answers);
    };
    return Fake{srv: $srv, base: $base, t: $t};
}

/**
 * Serve requests until the server shuts down.
 *
 * @param srv {httpd.Server} the server
 * @param answers {map of string to string} the answers
 * @return {list of string} each request as `METHOD path?query|Header=value|...`, a newline and the body
 */
func serveFake(srv as httpd.Server, answers as map of string to string) {
    def seen as list of string init [];
    def count as map of string to int init {};
    while (true) {
        def req as httpd.Request;
        try {
            $req = httpd.accept($srv);
        } catch (e) {
            return $seen;
        }
        def target as string init httpd.path($req);
        if (httpd.rawQuery($req) != "") {
            $target = $target + "?" + httpd.rawQuery($req);
        }
        def key as string init httpd.method($req) + " " + $target;
        if (not maps.has($count, $key)) {
            $count[$key] = 0;
        }
        $count[$key] = $count[$key] + 1;
        def line as list of string init [$key];
        for (def h in RECORDED) {
            if (httpd.header($req, $h) != "") {
                $line[] = $h + "=" + httpd.header($req, $h);
            }
        }
        $seen[] = strings.join($line, "|") + "\n" +
            convert.stringFromBytes("utf-8", httpd.body($req));
        def spec as string init "404\nContent-Type: application/json\n\n" +
            '{"error": {"message": "no answer for ' + $key +
            '", "type": "invalid_request_error", "param": null, "code": null}}';
        def nth as string init $key + "#" + convert.toString($count[$key]);
        if (maps.has($answers, $nth)) {
            $spec = $answers[$nth];
        } elseif (maps.has($answers, $key)) {
            $spec = $answers[$key];
        } elseif (maps.has($answers, httpd.method($req) + " " + httpd.path($req))) {
            $spec = $answers[httpd.method($req) + " " + httpd.path($req)];
        }
        def split as int init strings.indexOf($spec, "\n\n");
        def head as list of string init strings.split($spec[..$split], "\n");
        for (def h in $head[1..]) {
            def at as int init strings.indexOf($h, ": ");
            httpd.setHeader($req, $h[..$at], $h[$at + 2..]);
        }
        if ($head[0] == "SLEEP") {
            time.sleep(time.fromMilliseconds(1500));
            httpd.respond($req, 200, '{}');
        } else {
            httpd.respond($req, convert.toInt($head[0]), $spec[$split + 2..]);
        }
    }
}

/**
 * Stop a fake and return what it saw.
 *
 * @param f {Fake} the fake
 * @return {list of string} the requests
 */
func stopFake(f as Fake) {
    httpd.shutdown($f.srv);
    return task.wait($f.t);
}

/**
 * A client of a fake, with KEY.
 *
 * @param f {Fake} the fake
 * @return {Client} the client
 */
func fakeClient(f as Fake) {
    return withBaseUrl(client(KEY), $f.base);
}

/**
 * A JSON answer.
 *
 * @param status {int} the status
 * @param body {string} the JSON
 * @return {string} the answer for `startFake`
 */
func answer(status as int, body as string) {
    return convert.toString($status) + "\nContent-Type: application/json\n\n" + $body;
}

/**
 * The first line of a seen request: method, target and headers.
 *
 * @param seen {string} the request
 * @return {string} `METHOD path?query|Header=value|...`
 */
func headOf(seen as string) {
    return $seen[..strings.indexOf($seen, "\n")];
}

/**
 * The body of a seen request, as JSON.
 *
 * @param seen {string} the request
 * @return {json.Value} the body
 */
func bodyOf(seen as string) {
    return json.decode($seen[strings.indexOf($seen, "\n") + 1..]);
}

/**
 * Run a call that must throw an OpenaiError, and return it.
 *
 * @param c {Client} the client
 * @param path {string} the path for `call`
 * @return {OpenaiError} the error
 */
func callError(c as Client, path as string) {
    try {
        call($c, "GET", $path, json.decode("null"));
    } catch (e) {
        def err as OpenaiError init $e;
        return $err;
    }
    missed($path);
    return OpenaiError{
        kind: "",
        message: "",
        status: 0,
        type: "",
        code: "",
        param: "",
        requestId: "",
        retryAfterMs: 0,
        limits: {}
    };
}

func testClientDefaultsAndSettings() {
    def c as Client init client(KEY);
    testing.assertEqual($c.baseUrl, "https://api.openai.com/v1");
    testing.assertEqual($c.keyHeader, "bearer");
    testing.assertEqual($c.timeoutMs, DEFAULT_TIMEOUT_MS);
    testing.assertEqual($c.retries, DEFAULT_RETRIES);
    testing.assertEqual($c.maxBytes, DEFAULT_MAX_BYTES);
    testing.assertEqual(
        withBaseUrl($c, "http://127.0.0.1:11434/v1/").baseUrl,
        "http://127.0.0.1:11434/v1");
    testing.assertEqual(
        withBaseUrl($c, "https://openrouter.ai/api/v1").baseUrl,
        "https://openrouter.ai/api/v1");
    testing.assertEqual(withTimeout($c, 5000).timeoutMs, 5000);
    testing.assertEqual(withRetries($c, 0).retries, 0);
    testing.assertEqual(withMaxBytes($c, 65536).maxBytes, 65536);
    testing.assertTrue(withTls($c, http.TlsOptions{skipVerify: true}).tls.skipVerify);
    testing.assertEqual(withOrganization($c, "org-1").organization, "org-1");
    testing.assertEqual(withProject($c, "proj_1").project, "proj_1");
    testing.assertEqual(withHeader($c, "X-Title", "demo").headers["X-Title"], "demo");
    for (def bad in [
        "ftp://x",
        "https://x/?a=1",
        "api.openai.com/v1",
        "https://x/#f",
        "https://x:0",
        "https://x:70000",
        "https://x/a/../v1",
        "https://x/a b"
    ]) {
        try {
            withBaseUrl($c, $bad);
            missed($bad);
        } catch (e) {
            testing.assertEqual($e.kind, "openai");
            testing.assertContains($e.message, "a base URL is http(s)://host");
        }
    }
    for (def bad in [999, 86400001]) {
        try {
            withTimeout($c, $bad);
            missed(convert.toString($bad));
        } catch (e) {
            testing.assertContains($e.message, "the timeout must be 1000 to 86400000");
        }
    }
    try {
        withRetries($c, 11);
        missed("11 retries");
    } catch (e) {
        testing.assertContains($e.message, "the retries must be 0 to 10");
    }
    try {
        withMaxBytes($c, 1024);
        missed("a small cap");
    } catch (e) {
        testing.assertContains($e.message, "the largest reply must be");
    }
    for (def own in ["Authorization", "api-key", "content-type", "OpenAI-Project"]) {
        try {
            withHeader($c, $own, "x");
            missed($own);
        } catch (e) {
            testing.assertContains($e.message, "the client sets");
        }
    }
    try {
        withHeader($c, "Bad Name", "x");
        missed("a bad header name");
    } catch (e) {
        testing.assertContains($e.message, "a header name is");
    }
}

func testKeyNeverInAMessage() {
    try {
        client("sk-secret\r\nX: 1");
        missed("a key with CR LF");
    } catch (e) {
        testing.assertEqual($e.kind, "openai");
        testing.assertFalse(strings.contains($e.message, "secret"));
    }
    testing.assertEqual(cleaned("key sk-proj-AbCd1234efgh and more", 100), "key sk-*** and more");
    testing.assertEqual(cleaned("a\nb‮", 100), "a?b?");
}

func testPlainHttpOnlyToLoopback() {
    for (def ok in [
        "http://127.0.0.1:11434/v1",
        "http://localhost:8080/v1",
        "http://[::1]:8000/v1"
    ]) {
        checkPlain(withBaseUrl(client(""), $ok));
    }
    def lan as Client init withBaseUrl(client(KEY), "http://ollama.lan:11434/v1");
    try {
        models($lan);
        missed("plain http to the LAN");
    } catch (e) {
        testing.assertEqual($e.kind, "openai");
        testing.assertEqual($e.status, 0);
        testing.assertContains($e.message, "in clear: use https, or withPlainHttp");
        testing.assertFalse(strings.contains($e.message, KEY));
    }
    checkPlain(withPlainHttp($lan));
}

func testHeadersAndModels() {
    def f as Fake init startFake({"GET /v1/models": answer(200, MODELS_OLLAMA)});
    def c as Client init withHeader(
        withProject(withOrganization(fakeClient($f), "org-7"), "proj_7"),
        "X-Title",
        "deck test");
    def ms as list of Model init models($c);
    def seen as list of string init stopFake($f);
    testing.assertEqual(len($ms), 2);
    testing.assertEqual($ms[1].id, "qwen2.5:0.5b");
    testing.assertEqual($ms[1].ownedBy, "library");
    testing.assertEqual($ms[1].created, 1794694197);
    testing.assertEqual(
        headOf($seen[0]),
        "GET /v1/models|Authorization=Bearer " + KEY +
            "|OpenAI-Organization=org-7|OpenAI-Project=proj_7|X-Title=deck test");
}

func testNoKeyNoAuthorization() {
    def f as Fake init startFake({"GET /v1/models": answer(200, MODELS_OLLAMA)});
    models(withBaseUrl(client(""), $f.base));
    def seen as list of string init stopFake($f);
    testing.assertEqual(headOf($seen[0]), "GET /v1/models");
}

func testAzureV1() {
    def f as Fake init startFake({"POST /openai/v1/chat/completions": answer(200, CHAT_DOCS)});
    def root as string init $f.base[..len($f.base) - 3];
    def c as Client init azure($root + "/", "azure-key-1");
    testing.assertEqual($c.baseUrl, $root + "/openai/v1");
    def req as json.Value init addMessage(newRequest("my-gpt-deployment"), "user", "hi");
    testing.assertEqual(text(chat($c, $req)), "Hello! How can I assist you today?");
    def seen as list of string init stopFake($f);
    testing.assertEqual(
        headOf($seen[0]),
        "POST /openai/v1/chat/completions|Content-Type=application/json|api-key=azure-key-1");
    testing.assertEqual(json.asString(bodyOf($seen[0]), "/model"), "my-gpt-deployment");
    for (def bad in ["https://r.openai.azure.com/openai", "https://r.openai.azure.com/openai/v1/"]) {
        try {
            azure($bad, "k");
            missed($bad);
        } catch (e) {
            testing.assertContains($e.message, "the resource's root, without /openai");
        }
    }
}

func testAzureVersionedPaths() {
    def f as Fake init startFake({
        "POST /openai/deployments/dep-4o/chat/completions?api-version=2024-10-21": answer(
            200,
            CHAT_DOCS),
        "POST /openai/deployments/emb.small/embeddings?api-version=2024-10-21": answer(
            200,
            EMBED_DOCS),
        "GET /openai/models?api-version=2024-10-21": answer(
            200,
            '{"data": [{"id": "gpt-4o", "created_at": 1715558400, "object": "model", "status": "succeeded"}], "object": "list"}'),
        "GET /openai/deployments?x=1&api-version=2024-10-21": answer(200, '{"data": []}')
    });
    def root as string init $f.base[..len($f.base) - 3];
    def c as Client init azureVersioned($root, "azure-key-2", AZURE_API_VERSION);
    chat($c, addMessage(newRequest("dep-4o"), "user", "hi"));
    embeddings($c, json.decode('{"model": "emb.small", "input": "x"}'));
    def ms as list of Model init models($c);
    testing.assertEqual($ms[0].id, "gpt-4o");
    testing.assertEqual($ms[0].created, 1715558400);
    testing.assertEqual($ms[0].ownedBy, "");
    call($c, "GET", "/deployments?x=1", json.decode("null"));
    def seen as list of string init stopFake($f);
    testing.assertEqual(len($seen), 4);
    testing.assertEqual(
        headOf($seen[0]),
        "POST /openai/deployments/dep-4o/chat/completions?api-version=2024-10-21|Content-Type=application/json|api-key=azure-key-2");
    testing.assertEqual(
        headOf($seen[3]),
        "GET /openai/deployments?x=1&api-version=2024-10-21|api-key=azure-key-2");
    try {
        chat($c, addMessage(newRequest("../x"), "user", "hi"));
        missed("a deployment with ..");
    } catch (e) {
        testing.assertContains($e.message, "an Azure deployment is");
    }
    try {
        azureVersioned($root, "k", "2024-10");
        missed("a bad api-version");
    } catch (e) {
        testing.assertContains($e.message, "an api-version is YYYY-MM-DD");
    }
    testing.assertEqual(
        azureVersioned($root, "k", "2025-04-01-preview").azureVersion,
        "2025-04-01-preview");
}

func testErrorShapes() {
    def f as Fake init startFake({
        "GET /v1/key": "401\nContent-Type: application/json\nx-request-id: req_abc123\n\n" +
            ERROR_KEY,
        "GET /v1/param": answer(400, ERROR_PARAM),
        "GET /v1/llama": answer(400, ERROR_LLAMA),
        "GET /v1/vllm": answer(404, ERROR_VLLM),
        "GET /v1/azure": "404\nContent-Type: application/json\napim-request-id: 9f1e\n\n" +
            ERROR_AZURE,
        "GET /v1/ollama": answer(404, ERROR_OLLAMA),
        "GET /v1/plain": "404\nContent-Type: text/plain\n\n404 page not found",
        "GET /v1/html": "502\nContent-Type: text/html\n\n<html><body>Bad gateway</body></html>",
        "GET /v1/fastapi": answer(422, '{"detail": "Not Found"}'),
        "GET /v1/olderr": answer(500, '{"error": "llama runner process has terminated"}'),
        "GET /v1/echo": answer(400, '{"error": {"message": "bad key ' + KEY + '", "type": "x"}}'),
        "GET /v1/ok-error": answer(200, ERROR_RATE),
        "GET /v1/notjson": "200\nContent-Type: text/plain\n\nhello"
    });
    def c as Client init withRetries(fakeClient($f), 0);
    def e as OpenaiError init callError($c, "/key");
    testing.assertEqual($e.kind, "openai");
    testing.assertEqual($e.status, 401);
    testing.assertEqual($e.type, "invalid_request_error");
    testing.assertEqual($e.code, "invalid_api_key");
    testing.assertEqual($e.param, "");
    testing.assertEqual($e.requestId, "req_abc123");
    testing.assertContains(
        $e.message,
        "openai: call GET \"/key\": Incorrect API key provided: sk-*** You can");
    testing.assertContains(
        $e.message,
        "(HTTP 401, type invalid_request_error, code invalid_api_key)");
    $e = callError($c, "/param");
    testing.assertEqual($e.param, "max_tokens");
    testing.assertEqual($e.code, "unsupported_parameter");
    $e = callError($c, "/llama");
    testing.assertEqual($e.code, "400");
    testing.assertEqual($e.type, "exceed_context_size_error");
    testing.assertContains($e.message, "the request exceeds the available context size");
    $e = callError($c, "/vllm");
    testing.assertEqual($e.type, "NotFoundError");
    testing.assertEqual($e.code, "404");
    testing.assertContains($e.message, "The model does not exist.");
    $e = callError($c, "/azure");
    testing.assertEqual($e.code, "DeploymentNotFound");
    testing.assertEqual($e.type, "");
    testing.assertEqual($e.requestId, "9f1e");
    $e = callError($c, "/ollama");
    testing.assertEqual($e.type, "not_found_error");
    testing.assertContains($e.message, "model 'nope' not found (HTTP 404, type not_found_error)");
    testing.assertContains(callError($c, "/plain").message, ": 404 page not found (HTTP 404)");
    $e = callError($c, "/html");
    testing.assertEqual($e.status, 502);
    testing.assertContains($e.message, ": Bad Gateway (HTTP 502)");
    testing.assertContains(callError($c, "/fastapi").message, ": Not Found (HTTP 422)");
    testing.assertContains(
        callError($c, "/olderr").message,
        "llama runner process has terminated (HTTP 500)");
    $e = callError($c, "/echo");
    testing.assertFalse(strings.contains($e.message, KEY));
    testing.assertContains($e.message, "bad key *** (HTTP 400");
    $e = callError($c, "/ok-error");
    testing.assertEqual($e.status, 200);
    testing.assertEqual($e.code, "rate_limit_exceeded");
    $e = callError($c, "/notjson");
    testing.assertContains($e.message, "the reply is not JSON: \"hello\"");
    stopFake($f);
}

func testRetriesHonourRetryAfter() {
    def f as Fake init startFake({
        "GET /v1/ms#1": "429\nContent-Type: application/json\nretry-after-ms: 5\n\n" + ERROR_RATE,
        "GET /v1/ms": answer(200, '{"ok": true}'),
        "GET /v1/sec#1": "503\nretry-after: 0\n\nbusy",
        "GET /v1/sec#2": "500\nretry-after: 0.01\n\nbusy",
        "GET /v1/sec": answer(200, '{"ok": 2}'),
        "GET /v1/always": "503\nretry-after-ms: 1\n\nbusy",
        "GET /v1/quota": "429\nContent-Type: application/json\nretry-after-ms: 1\n\n" + ERROR_QUOTA,
        "GET /v1/noretry": "500\nx-should-retry: false\nretry-after-ms: 1\n\noops",
        "GET /v1/long": "429\nretry-after: 120\n\nslow down",
        "GET /v1/bad": "400\n\nno"
    });
    def c as Client init fakeClient($f);
    testing.assertTrue(json.asBool(call($c, "GET", "/ms", json.decode("null")), "/ok"));
    testing.assertEqual(json.asInt(call($c, "GET", "/sec", json.decode("null")), "/ok"), 2);
    testing.assertEqual(callError($c, "/always").status, 503);
    testing.assertEqual(callError(withRetries($c, 0), "/always").status, 503);
    def e as OpenaiError init callError($c, "/quota");
    testing.assertEqual($e.type, "insufficient_quota");
    callError($c, "/noretry");
    callError($c, "/long");
    callError($c, "/bad");
    def seen as list of string init stopFake($f);
    def counts as map of string to int init {};
    for (def s in $seen) {
        def k as string init headOf($s)[..strings.indexOf(headOf($s), "|")];
        if (not maps.has($counts, $k)) {
            $counts[$k] = 0;
        }
        $counts[$k] = $counts[$k] + 1;
    }
    testing.assertEqual(
        $counts,
        {
            "GET /v1/ms": 2,
            "GET /v1/sec": 3,
            "GET /v1/always": 4,
            "GET /v1/quota": 1,
            "GET /v1/noretry": 1,
            "GET /v1/long": 1,
            "GET /v1/bad": 1
        });
}

func testRetryWaits() {
    def r as http.BytesResponse init http.BytesResponse{
        status: 429,
        statusText: "Too Many Requests",
        headers: {},
        body: convert.bytesFromString("utf-8", "")
    };
    testing.assertEqual(retryWait($r, 0), 500);
    testing.assertEqual(retryWait($r, 1), 1000);
    testing.assertEqual(retryWait($r, 3), 4000);
    testing.assertEqual(retryWait($r, 9), 8000);
    # an HTTP date: one passed is 0, one in 30 s about 30000, one past the minute is not taken
    $r.headers = {"retry-after": "Wed, 21 Oct 2026 07:28:00 GMT"};
    testing.assertEqual(retryWait($r, 1), 0);
    def later as string init time.format(
        time.add(time.utc(), time.fromSeconds(30)),
        "%a, %d %b %Y %H:%M:%S GMT");
    $r.headers = {"retry-after": $later};
    def wait as int init retryWait($r, 0);
    testing.assertTrue($wait > 28000 and $wait <= 30000);
    $r.headers = {
        "retry-after": time.format(
            time.add(time.utc(), time.fromSeconds(300)),
            "%a, %d %b %Y %H:%M:%S GMT")
    };
    testing.assertEqual(retryWait($r, 0), -1);
    $r.headers = {"retry-after": "Wed, 21 Oct 2026 07:28:00 CET"};
    testing.assertEqual(retryWait($r, 1), 1000);
    $r.headers = {"retry-after": "2"};
    testing.assertEqual(retryWait($r, 0), 2000);
    $r.headers = {"retry-after": "2", "retry-after-ms": "1500.5"};
    testing.assertEqual(retryWait($r, 0), 1500);
    $r.headers = {"retry-after": "61"};
    testing.assertEqual(retryWait($r, 0), -1);
    # a wait of ten digits or more is over the minute, not a malformed header
    $r.headers = {"retry-after-ms": "999999999999"};
    testing.assertEqual(retryWait($r, 0), -1);
    $r.headers = {"retry-after": "1000000000"};
    testing.assertEqual(retryWait($r, 0), -1);
}

func testRetries408And409() {
    def f as Fake init startFake({
        "GET /v1/models#1": "408\nretry-after-ms: 0\n\n",
        "GET /v1/models#2": "409\nContent-Type: application/json\nretry-after-ms: 0\n\n" +
            '{"error": {"message": "busy", "type": "conflict", "param": null, "code": null}}',
        "GET /v1/models#3": answer(200, MODELS_OLLAMA)
    });
    testing.assertEqual(len(models(fakeClient($f))), 2);
    testing.assertEqual(len(stopFake($f)), 3);
}

func testARefusedConnectionIsRetried() {
    def l as net.Listener init net.listen("127.0.0.1:0");
    def addr as string init net.address($l);
    net.close($l);
    def c as Client init withRetries(withBaseUrl(client(""), "http://" + $addr + "/v1"), 1);
    def start as int init time.unixMillis(time.now());
    try {
        models($c);
        missed("a closed port");
    } catch (e) {
        testing.assertContains($e.message, "cannot reach");
    }
    # one retry after the first backoff, 500 ms
    testing.assertTrue(time.unixMillis(time.now()) - $start >= 450);
}

func testErrorsCarryTheWaitAndTheLimits() {
    def f as Fake init startFake({
        "GET /v1/models": "429\nContent-Type: application/json\nRetry-After: 120\n" +
            "X-RateLimit-Limit-Requests: 60\nx-ratelimit-remaining-requests: 0\n" +
            "x-ratelimit-reset-requests: 1m59s\nx-request-id: req_9\n\n" + ERROR_RATE
    });
    try {
        models(fakeClient($f));
        missed("a 429");
    } catch (e) {
        def err as OpenaiError init $e;
        testing.assertEqual($err.status, 429);
        testing.assertEqual($err.retryAfterMs, 120000);
        testing.assertEqual($err.limits["x-ratelimit-limit-requests"], "60");
        testing.assertEqual($err.limits["x-ratelimit-remaining-requests"], "0");
        testing.assertEqual($err.limits["x-ratelimit-reset-requests"], "1m59s");
        testing.assertEqual($err.limits["retry-after"], "120");
        testing.assertFalse(maps.has($err.limits, "x-request-id"));
    }
    # over a minute: thrown at once, not waited for
    testing.assertEqual(len(stopFake($f)), 1);
}

func testAHugeRetryAfterIsNotRetried() {
    def f as Fake init startFake({
        "GET /v1/models": "429\nContent-Type: application/json\nRetry-After: 1000000000\n\n" +
            '{"error": {"message": "slow down", "type": "requests", "param": null, "code": null}}'
    });
    try {
        models(fakeClient($f));
        missed("a 429");
    } catch (e) {
        testing.assertEqual($e.status, 429);
    }
    testing.assertEqual(len(stopFake($f)), 1);
}

func testServerTextNeverShowsTheKey() {
    def key as string init "gsk_Q2xhdWRlVGVzdEtleTAxMjM0NTY3";
    def f as Fake init startFake({
        "GET /v1/models": answer(
            401,
            '{"error": {"message": "bad key Bearer ' + $key +
                '", "type": "auth ' + $key + '", "param": null, "code": null}}'),
        "GET /v1/page": "200\nContent-Type: text/html\n\n<html>you sent " + $key + "</html>",
        "GET /v1/plain": "403\nContent-Type: text/plain\n\n" + strings.repeat("x", 490) + $key
    });
    def c as Client init withBaseUrl(client($key), $f.base);
    for (def path in ["/models", "/page", "/plain"]) {
        try {
            call($c, "GET", $path, json.decode("null"));
            missed($path);
        } catch (e) {
            def err as OpenaiError init $e;
            testing.assertFalse(strings.contains($err.message, "gsk_Q2xh"));
            testing.assertFalse(strings.contains($err.type, "gsk_Q2xh"));
        }
    }
    stopFake($f);
    testing.assertEqual(unkeyed("a key-1234 b", "key-1234"), "a *** b");
    testing.assertEqual(unkeyed("a key b", "key"), "a key b");
}

func testWithHeaderKeepsOneHeaderPerName() {
    def c as Client init withHeader(withHeader(client(""), "x-title", "a"), "X-Title", "b");
    testing.assertEqual($c.headers, {"X-Title": "b"});
    def h as map of string to string init headersOf(withHeader($c, "accept", "text/plain"), false);
    testing.assertEqual($h, {"X-Title": "b", "accept": "text/plain"});
    testing.assertEqual(headersOf($c, false)["Accept"], "application/json");
}

func testReplyCap() {
    def big as string init '{"pad": "' + strings.repeat("x", 70000) + '"}';
    def f as Fake init startFake({"GET /v1/big": answer(200, $big)});
    def c as Client init withMaxBytes(fakeClient($f), 65536);
    try {
        call($c, "GET", "/big", json.decode("null"));
        missed("a reply over the cap");
    } catch (e) {
        testing.assertEqual($e.kind, "limit");
        testing.assertContains(
            $e.message,
            "openai: call GET \"/big\": the reply is over 65536 bytes");
    }
    testing.assertEqual(
        len(json.asString(
            call(withMaxBytes($c, 131072), "GET", "/big", json.decode("null")),
            "/pad")),
        70000);
    stopFake($f);
}

func testDeadline() {
    def f as Fake init startFake({"GET /v1/slow": "SLEEP\n\n"});
    def c as Client init withTimeout(fakeClient($f), 1000);
    try {
        call($c, "GET", "/slow", json.decode("null"));
        missed("a slow server");
    } catch (e) {
        testing.assertEqual($e.kind, "timeout");
        testing.assertContains($e.message, "openai: call GET \"/slow\": no reply within 1000 ms");
    }
    stopFake($f);
}

func testCancelledPassesOn() {
    def f as Fake init startFake({"GET /v1/slow": "SLEEP\n\n"});
    def c as Client init fakeClient($f);
    def t as task of json.Value init spawn {
        return call($c, "GET", "/slow", json.decode("null"));
    };
    time.sleep(time.fromMilliseconds(200));
    task.cancel($t);
    try {
        task.wait($t);
        missed("a cancelled call");
    } catch (e) {
        testing.assertEqual($e.kind, "cancelled");
    }
    stopFake($f);
}

func testClosedMidReply() {
    def l as net.Listener init net.listen("127.0.0.1:0");
    def addr as string init net.address($l);
    def t as task of null init spawn {
        def conn as net.Conn init net.accept($l);
        net.readBytes($conn, 4096);
        net.writeBytes(
            $conn,
            convert.bytesFromString(
                "utf-8",
                "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 100\r\n\r\n" +
                    '{"choi'));
        net.close($conn);
        return null;
    };
    try {
        models(withBaseUrl(client(""), "http://" + $addr + "/v1"));
        missed("a reply cut short");
    } catch (e) {
        testing.assertEqual($e.kind, "closed");
        testing.assertContains($e.message, "openai: models: the server closed the connection");
    }
    task.wait($t);
    net.close($l);
}

func testUnreachable() {
    def l as net.Listener init net.listen("127.0.0.1:0");
    def addr as string init net.address($l);
    net.close($l);
    try {
        models(withBaseUrl(client(KEY), "http://" + $addr + "/v1"));
        missed("a closed port");
    } catch (e) {
        testing.assertEqual($e.kind, "openai");
        testing.assertEqual($e.status, 0);
        testing.assertContains(
            $e.message,
            "openai: models: cannot reach \"http://" + $addr + "/v1\"");
        testing.assertFalse(strings.contains($e.message, KEY));
    }
}

func testCall() {
    def f as Fake init startFake({
        "GET /v1/models/gpt-6-astra": answer(200, '{"id": "gpt-6-astra", "object": "model"}'),
        "POST /v1/moderations": answer(200, '{"results": [{"flagged": false}]}'),
        "DELETE /v1/chat/completions/c1": answer(204, '')
    });
    def c as Client init fakeClient($f);
    testing.assertEqual(
        json.asString(call($c, "GET", "/models/gpt-6-astra", json.decode("null")), "/id"),
        "gpt-6-astra");
    def body as json.Value init json.map({"input": "hello"});
    testing.assertFalse(json.asBool(call($c, "POST", "/moderations", $body), "/results/0/flagged"));
    testing.assertTrue(json.isNull(call($c, "DELETE", "/chat/completions/c1", json.decode("null"))));
    def seen as list of string init stopFake($f);
    testing.assertEqual(headOf($seen[0]), "GET /v1/models/gpt-6-astra|Authorization=Bearer " + KEY);
    testing.assertEqual(
        headOf($seen[1]),
        "POST /v1/moderations|Content-Type=application/json|Authorization=Bearer " + KEY);
    testing.assertEqual(bodyOf($seen[1]), $body);
    for (def bad in [
        "models",
        "//evil.example/x",
        "/a/../b",
        "/a/./b",
        "/a b",
        "/a#b",
        "/..",
        "/a\\b",
        "/%2e%2e/admin",
        "/a/%2E/b",
        "/a/.%2e?x=1",
        "/a\u0001b",
        "/a\u007fb"
    ]) {
        try {
            call($c, "GET", $bad, json.decode("null"));
            missed($bad);
        } catch (e) {
            testing.assertContains($e.message, "call: the path starts with one /");
        }
    }
    try {
        call($c, "HEAD", "/models", json.decode("null"));
        missed("HEAD");
    } catch (e) {
        testing.assertContains($e.message, "call: the method is GET, POST, PUT, PATCH or DELETE");
    }
}
