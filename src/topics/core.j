# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# openai - core: the client and its settings, Azure, the HTTP exchange with
# its deadline, cap and retries, errors, JSON readers, `models` and `call`.
# Spliced into openai.j via include.

/** The OpenAI API's base URL. */
export def const DEFAULT_BASE_URL as string init "https://api.openai.com/v1";

/** How long one request may take, in milliseconds: 10 minutes, for long generations. */
export def const DEFAULT_TIMEOUT_MS as int init 600000;

/** How many times a request is retried on 408, 409, 429, 5xx or a connection refused or reset. */
export def const DEFAULT_RETRIES as int init 2;

/** The largest reply read, in bytes: 32 MiB. */
export def const DEFAULT_MAX_BYTES as int init 33554432;

/** The largest tool input a tool loop hands to a handler, in bytes: 1 MiB. */
export def const DEFAULT_MAX_TOOL_INPUT as int init 1048576;

/** The Azure OpenAI `api-version` that `azureVersioned` callers usually want: the latest GA one. */
export def const AZURE_API_VERSION as string init "2024-10-21";

# the first retry's wait without a retry-after, doubled each time up to MAX_BACKOFF_MS
def const BACKOFF_MS as int init 500;
def const MAX_BACKOFF_MS as int init 8000;

# a server asking to wait longer than this is not retried: the error is thrown
def const MAX_RETRY_WAIT_MS as int init 60000;

# the longest wait a retry header is read as, about 31 years: more is cut to it
def const MAX_NAMED_WAIT_MS as int init 1000000000000;

# the most rate-limit headers an error keeps
def const MAX_LIMIT_HEADERS as int init 32;

# the generic error kinds, passed on unchanged
def const GENERIC_KINDS as list of string init ["limit", "timeout", "closed", "cancelled"];

# what an error message never shows: control characters and the bidi controls
# that reorder a terminal line
def const UNSHOWN as string init '[\x00-\x1f\x7f-\x9f\x{061c}\x{200b}-\x{200f}\x{2028}-\x{202e}\x{2060}-\x{2069}\x{feff}]';

# an OpenAI-style secret key, masked in a server's message
def const KEY_FORM as string init 'sk-[A-Za-z0-9_*.-]{4,}';

# a base URL: http(s), a host, an optional port and plain path segments
def const URL_FORM as string init '^(https?)://(\[[0-9A-Fa-f:.]+\]|[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)*)(:([0-9]{1,5}))?(/[A-Za-z0-9._~-]+)*$';

# an Azure deployment name, which goes into the path
def const DEPLOYMENT as string init '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$';

# an Azure api-version
def const API_VERSION as string init '^[0-9]{4}-[0-9]{2}-[0-9]{2}(-preview)?$';

# an HTTP header name
def const HEADER_NAME as string init '^[A-Za-z0-9!#$%&*+.^_`|~-]{1,64}$';

# the headers the client sets itself, which withHeader refuses
def const OWN_HEADERS as list of string init [
    "authorization",
    "api-key",
    "content-type",
    "content-length",
    "host",
    "openai-organization",
    "openai-project"
];

# the hosts plain http is allowed to without `withPlainHttp`
def const LOOPBACK as list of string init ["127.0.0.1", "localhost", "[::1]"];

/**
 * How to reach the API and who is asking. Build it with `client`, `azure`
 * or `azureVersioned`, change it with the `with*` functions. It holds the
 * API key: do not print it.
 *
 * @field baseUrl {string} the API's URL without a trailing slash, such as `https://api.openai.com/v1`; for `azureVersioned` the resource's endpoint
 * @field apiKey {string} the key, `""` for a server that needs none
 * @field keyHeader {string} `"bearer"` (`Authorization: Bearer`) or `"api-key"` (Azure's `api-key` header)
 * @field azureVersion {string} the `api-version` of an `azureVersioned` client, which puts the deployment in the path; `""` otherwise
 * @field organization {string} the `OpenAI-Organization` header, `""` for none
 * @field project {string} the `OpenAI-Project` header, `""` for none
 * @field headers {map of string to string} more headers sent with every request
 * @field tls {http.TlsOptions} certificate checks for an `https` URL
 * @field allowPlainHttp {bool} whether plain `http` to another machine is allowed (the key then crosses the network in clear)
 * @field timeoutMs {int} how long one attempt may take
 * @field retries {int} how many times a failed attempt is retried (408, 409, 429, 5xx, a connection refused or reset)
 * @field maxBytes {int} the largest reply read
 * @field maxToolInput {int} the largest tool input, in bytes, a tool loop hands to a handler
 */
export def struct Client {
    baseUrl as string,
    apiKey as string,
    keyHeader as string,
    azureVersion as string,
    organization as string,
    project as string,
    headers as map of string to string,
    tls as http.TlsOptions,
    allowPlainHttp as bool,
    timeoutMs as int,
    retries as int,
    maxBytes as int,
    maxToolInput as int
};

/**
 * An error of this deck: a request the server refused, a reply that is not
 * what the API sends, a server that cannot be reached, or an argument
 * refused before sending. Every throw of kind `"openai"` is this struct.
 *
 * @field kind {string} always "openai"
 * @field message {string} `openai: <request>: <why>`, with `(HTTP nnn)` when the server answered
 * @field status {int} the HTTP status, 0 when no server answered or the deck refused locally
 * @field type {string} the error's `type`, such as `invalid_request_error` or `insufficient_quota`; `""` when absent
 * @field code {string} the error's `code`, such as `model_not_found` or `rate_limit_exceeded` (a number is given as its digits); `""` when absent
 * @field param {string} the request field the error is about, such as `messages`; `""` when absent
 * @field requestId {string} the `x-request-id` (or Azure's `apim-request-id`) header, for the provider's support; `""` when absent
 * @field retryAfterMs {int} how long the server asked to wait (`retry-after-ms`, else `retry-after` in seconds or as an HTTP date), in milliseconds; 0 when it named no wait
 * @field limits {map of string to string} the server's rate-limit headers, names lower-cased: `x-ratelimit-limit-requests`, `x-ratelimit-remaining-tokens`, `x-ratelimit-reset-requests`, ..., `retry-after`, `retry-after-ms`; empty when it sent none
 */
export def struct OpenaiError {
    kind as string,
    message as string,
    status as int,
    type as string,
    code as string,
    param as string,
    requestId as string,
    retryAfterMs as int,
    limits as map of string to string
};

/**
 * Throw an OpenaiError that no server answered.
 *
 * @param message {string} what went wrong, without the `openai: ` prefix
 * @throws {OpenaiError} kind "openai", always
 */
func fail(message as string) {
    throw OpenaiError{
        kind: "openai",
        message: "openai: " + $message,
        status: 0,
        type: "",
        code: "",
        param: "",
        requestId: "",
        retryAfterMs: 0,
        limits: {}
    };
}

/**
 * Throw a reached cap: kind "limit".
 *
 * @param message {string} what was over the cap, without the `openai: ` prefix
 * @throws {Error} kind "limit", always
 */
func failLimit(message as string) {
    throw Error{kind: "limit", message: "openai: " + $message};
}

/**
 * Server-controlled text made safe for a message: control and bidi
 * characters as `?`, an `sk-` key masked, at most a number of characters.
 *
 * @param s {string} the text
 * @param most {int} the most characters kept
 * @return {string} the text
 */
func cleaned(s as string, most as int) {
    def text as string init $s;
    if (len($text) > $most) {
        $text = $text[..$most] + "...";
    }
    return regex.replace(KEY_FORM, regex.replace(UNSHOWN, $text, "?"), "sk-***");
}

/**
 * Server text with the client's own key masked, whatever its form (an
 * Azure, Groq or Mistral key is not `sk-...`). A key under 8 characters is
 * left alone: masking it would garble the text, and it is no secret.
 *
 * @param s {string} the text
 * @param key {string} the client's API key, `""` for none
 * @return {string} the text
 */
func unkeyed(s as string, key as string) {
    if (len($key) < 8) {
        return $s;
    }
    return strings.replace($s, $key, "***");
}

/**
 * Text quoted for an error message.
 *
 * @param s {string} the text
 * @return {string} the text in double quotes, cleaned and cut at 200 characters
 */
func shown(s as string) {
    return "\"" + cleaned($s, 200) + "\"";
}

/**
 * Refuse an int outside a range.
 *
 * @param value {int} the value
 * @param low {int} the smallest allowed
 * @param high {int} the largest allowed
 * @param what {string} what the value is
 */
func checkRange(value as int, low as int, high as int, what as string) {
    if ($value < $low or $value > $high) {
        fail(io.sprintf("%s must be %d to %d, got %d", $what, $low, $high, $value));
    }
}

/**
 * Refuse a header value that would break the request: a control
 * character, or more than 4096 characters. The value is not shown, it may
 * be a key.
 *
 * @param value {string} the value
 * @param what {string} what it is
 */
func checkHeaderValue(value as string, what as string) {
    if (len($value) > 4096 or regex.matches('[\x00-\x1f\x7f]', $value)) {
        fail($what + " holds a control character or is over 4096 characters");
    }
}

/**
 * A base URL without trailing slashes, refused when it is not an absolute
 * http(s) URL without query or fragment.
 *
 * @param url {string} the URL
 * @param what {string} what it is, for the message
 * @return {string} the URL
 */
func baseOf(url as string, what as string) {
    def base as string init $url;
    while (strings.endsWith($base, "/")) {
        $base = $base[..len($base) - 1];
    }
    def m as regex.Match init regex.find(URL_FORM, $base);
    if ($m.start < 0 or regex.matches('/\.+(/|$)', $base) or
        ($m.groups[6] != "" and
        (convert.toInt($m.groups[6]) < 1 or convert.toInt($m.groups[6]) > 65535))) {
        fail($what +
            " is http(s)://host[:port][/path], port 1 to 65535, the path plain segments, got " +
            shown($url));
    }
    return $base;
}

/**
 * A client for the OpenAI API (`DEFAULT_BASE_URL`) with a key sent as
 * `Authorization: Bearer`. Point it at another server with `withBaseUrl`;
 * a local server that needs no key takes `""`.
 *
 * @param apiKey {string} the API key, `""` for none
 * @return {Client} the client
 * @throws {OpenaiError} when the key holds a control character
 * @example
 *   def c as openai.Client init openai.client(os.getEnv("OPENAI_API_KEY"));
 *   def local as openai.Client init openai.withBaseUrl(openai.client(""), "http://127.0.0.1:11434/v1");
 */
export func client(apiKey as string) {
    checkHeaderValue($apiKey, "the API key");
    return Client{
        baseUrl: DEFAULT_BASE_URL,
        apiKey: $apiKey,
        keyHeader: "bearer",
        azureVersion: "",
        organization: "",
        project: "",
        headers: {},
        tls: http.TlsOptions{},
        allowPlainHttp: false,
        timeoutMs: DEFAULT_TIMEOUT_MS,
        retries: DEFAULT_RETRIES,
        maxBytes: DEFAULT_MAX_BYTES,
        maxToolInput: DEFAULT_MAX_TOOL_INPUT
    };
}

/**
 * The client talking to another OpenAI-compatible server: the URL that
 * `/chat/completions` hangs below, such as `http://127.0.0.1:11434/v1`
 * (Ollama), `http://127.0.0.1:8000/v1` (vLLM), `http://127.0.0.1:8080/v1`
 * (llama.cpp), `https://openrouter.ai/api/v1` or
 * `https://api.groq.com/openai/v1`. Plain `http` to another machine is
 * refused when a request is sent: add `withPlainHttp`.
 *
 * @param c {Client} the client
 * @param url {string} the base URL
 * @return {Client} the client
 * @throws {OpenaiError} when the URL is not an absolute http(s) URL without query or fragment
 */
export func withBaseUrl(c as Client, url as string) {
    $c.baseUrl = baseOf($url, "a base URL");
    return $c;
}

/**
 * A client for Azure OpenAI's v1 API: `<endpoint>/openai/v1`, the key in
 * the `api-key` header, no `api-version`. The request's `model` is the
 * deployment name. For a Microsoft Entra ID token instead of a key, use
 * `withBaseUrl(client(token), endpoint + "/openai/v1")`.
 *
 * @param endpoint {string} the resource's endpoint, such as `https://myres.openai.azure.com`
 * @param apiKey {string} the resource's key
 * @return {Client} the client
 * @throws {OpenaiError} when the endpoint is not an http(s) URL or already ends in `/openai` or `/openai/v1`
 * @example
 *   def az as openai.Client init openai.azure("https://myres.openai.azure.com", os.getEnv("AZURE_OPENAI_API_KEY"));
 */
export func azure(endpoint as string, apiKey as string) {
    def c as Client init client($apiKey);
    $c.baseUrl = azureEndpoint($endpoint) + "/openai/v1";
    $c.keyHeader = "api-key";
    return $c;
}

/**
 * A client for Azure OpenAI's dated API: the deployment in the path
 * (`/openai/deployments/<model>/chat/completions`), the `api-version`
 * query on every request, the key in the `api-key` header. The request's
 * `model` names the deployment and is sent in the body too.
 *
 * @param endpoint {string} the resource's endpoint, such as `https://myres.openai.azure.com`
 * @param apiKey {string} the resource's key
 * @param apiVersion {string} the `api-version`, such as `AZURE_API_VERSION` or `2025-04-01-preview`
 * @return {Client} the client
 * @throws {OpenaiError} when the endpoint or the version is malformed
 */
export func azureVersioned(endpoint as string, apiKey as string, apiVersion as string) {
    if (not regex.matches(API_VERSION, $apiVersion)) {
        fail("an api-version is YYYY-MM-DD with an optional -preview, got " + shown($apiVersion));
    }
    def c as Client init client($apiKey);
    $c.baseUrl = azureEndpoint($endpoint);
    $c.keyHeader = "api-key";
    $c.azureVersion = $apiVersion;
    return $c;
}

/**
 * An Azure endpoint, checked: a base URL not ending in `/openai` or
 * `/openai/v1`, which the deck adds itself.
 *
 * @param endpoint {string} the endpoint
 * @return {string} the endpoint without a trailing slash
 */
func azureEndpoint(endpoint as string) {
    def base as string init baseOf($endpoint, "an Azure endpoint");
    if (strings.endsWith($base, "/openai") or strings.endsWith($base, "/openai/v1")) {
        fail("an Azure endpoint is the resource's root, without /openai: got " + shown($endpoint));
    }
    return $base;
}

/**
 * The client sending `OpenAI-Organization`, for a key in several
 * organizations.
 *
 * @param c {Client} the client
 * @param id {string} the organization id, such as `org-...`; `""` for none
 * @return {Client} the client
 */
export func withOrganization(c as Client, id as string) {
    checkHeaderValue($id, "the organization");
    $c.organization = $id;
    return $c;
}

/**
 * The client sending `OpenAI-Project`, for a key in several projects.
 *
 * @param c {Client} the client
 * @param id {string} the project id, such as `proj_...`; `""` for none
 * @return {Client} the client
 */
export func withProject(c as Client, id as string) {
    checkHeaderValue($id, "the project");
    $c.project = $id;
    return $c;
}

/**
 * The client sending one more header with every request, such as
 * OpenRouter's `HTTP-Referer` and `X-Title`. The headers the client sets
 * itself (`Authorization`, `api-key`, `Content-Type`, `OpenAI-Organization`,
 * `OpenAI-Project`, ...) are refused. A name given again, in any case,
 * replaces the earlier value; `Accept` replaces the client's own.
 *
 * @param c {Client} the client
 * @param name {string} the header name
 * @param value {string} its value
 * @return {Client} the client
 */
export func withHeader(c as Client, name as string, value as string) {
    if (not regex.matches(HEADER_NAME, $name)) {
        fail("a header name is 1 to 64 token characters, got " + shown($name));
    }
    for (def own in OWN_HEADERS) {
        if (strings.lower($name) == $own) {
            fail("the client sets " + shown($name) + " itself");
        }
    }
    checkHeaderValue($value, "the header " + shown($name));
    # one header per name: the same name in another case replaces it
    def kept as map of string to string init {};
    for (def k in $c.headers) {
        if (strings.lower($k) != strings.lower($name)) {
            $kept[$k] = $c.headers[$k];
        }
    }
    $kept[$name] = $value;
    $c.headers = $kept;
    return $c;
}

/**
 * The client allowed to use plain `http` to another machine, such as an
 * Ollama server on the LAN. The key and every prompt cross the network in
 * clear.
 *
 * @param c {Client} the client
 * @return {Client} the client
 */
export func withPlainHttp(c as Client) {
    $c.allowPlainHttp = true;
    return $c;
}

/**
 * The client with certificate options for `https`: `caCert` for a server
 * with a certificate from a private CA.
 *
 * @param c {Client} the client
 * @param tls {http.TlsOptions} the options (`caCert`, `skipVerify`)
 * @return {Client} the client
 */
export func withTls(c as Client, tls as http.TlsOptions) {
    $c.tls = $tls;
    return $c;
}

/**
 * The client with another deadline for each attempt of a request.
 *
 * @param c {Client} the client
 * @param ms {int} 1000 to 86400000 milliseconds
 * @return {Client} the client
 */
export func withTimeout(c as Client, ms as int) {
    checkRange($ms, 1000, 86400000, "the timeout");
    $c.timeoutMs = $ms;
    return $c;
}

/**
 * The client retrying a failed attempt another number of times: a 408,
 * 409, 429 or 5xx, or a connection refused or reset.
 *
 * @param c {Client} the client
 * @param n {int} 0 (no retries) to 10
 * @return {Client} the client
 */
export func withRetries(c as Client, n as int) {
    checkRange($n, 0, 10, "the retries");
    $c.retries = $n;
    return $c;
}

/**
 * The client with another cap on replies. A batch of large embeddings
 * needs more than the default: 2048 vectors of 3072 floats are about
 * 130 MB of JSON, or a third of that as base64.
 *
 * @param c {Client} the client
 * @param most {int} 65536 to 1073741824 bytes
 * @return {Client} the client
 */
export func withMaxBytes(c as Client, most as int) {
    checkRange($most, 65536, 1073741824, "the largest reply");
    $c.maxBytes = $most;
    return $c;
}

/**
 * The client with another cap on tool input: in `runTools` and
 * `runToolsWith`, a call whose arguments (or custom tool input) are over
 * it is answered with a `toolError`, and the handler is not called. Model
 * output this large is a runaway or hostile, and parsing it costs about 15
 * times its size in memory.
 *
 * @param c {Client} the client
 * @param most {int} 1024 to 1073741824 bytes
 * @return {Client} the client
 */
export func withMaxToolInput(c as Client, most as int) {
    checkRange($most, 1024, 1073741824, "the largest tool input");
    $c.maxToolInput = $most;
    return $c;
}

/**
 * Refuse plain http to another machine without `allowPlainHttp`.
 *
 * @param c {Client} the client
 */
func checkPlain(c as Client) {
    def m as regex.Match init regex.find(URL_FORM, $c.baseUrl);
    if ($m.start < 0) {
        fail("the client's base URL was changed to " + shown($c.baseUrl) + ": use withBaseUrl");
    }
    if ($m.groups[0] == "http" and not $c.allowPlainHttp and
        not lists.contains(LOOPBACK, strings.lower($m.groups[1]))) {
        fail("plain http to " + shown($m.groups[1]) +
            " would send the key and the prompts in clear: use https, or withPlainHttp");
    }
}

/**
 * The URL of an API path. An `azureVersioned` client puts `/openai`, and
 * for a deployment `/deployments/<deployment>`, before it, and adds the
 * `api-version`.
 *
 * @param c {Client} the client
 * @param path {string} the path below the base URL, such as `/chat/completions`, with an optional query
 * @param deployment {string} the request's model, which an `azureVersioned` client puts in the path; `""` for a path without one
 * @return {string} the URL
 */
func urlOf(c as Client, path as string, deployment as string) {
    if ($c.azureVersion == "") {
        return $c.baseUrl + $path;
    }
    def prefix as string init "/openai";
    if ($deployment != "") {
        if (not regex.matches(DEPLOYMENT, $deployment)) {
            fail("an Azure deployment is 1 to 64 letters, digits, ., _ and -, got " +
                shown($deployment));
        }
        $prefix = $prefix + "/deployments/" + $deployment;
    }
    def sep as string init "?";
    if (strings.contains($path, "?")) {
        $sep = "&";
    }
    return $c.baseUrl + $prefix + $path + $sep + "api-version=" + $c.azureVersion;
}

/**
 * The headers of every request.
 *
 * @param c {Client} the client
 * @param hasBody {bool} whether a JSON body is sent
 * @return {map of string to string} the headers
 */
func headersOf(c as Client, hasBody as bool) {
    def h as map of string to string init {};
    def accept as bool init false;
    for (def k in $c.headers) {
        $h[$k] = $c.headers[$k];
        $accept = $accept or strings.lower($k) == "accept";
    }
    if (not $accept) {
        $h["Accept"] = "application/json";
    }
    if ($c.apiKey != "") {
        checkHeaderValue($c.apiKey, "the API key");
        if ($c.keyHeader == "api-key") {
            $h["api-key"] = $c.apiKey;
        } else {
            $h["Authorization"] = "Bearer " + $c.apiKey;
        }
    }
    if ($c.organization != "") {
        $h["OpenAI-Organization"] = $c.organization;
    }
    if ($c.project != "") {
        $h["OpenAI-Project"] = $c.project;
    }
    if ($hasBody) {
        $h["Content-Type"] = "application/json";
    }
    return $h;
}

/**
 * One attempt of a request: the response, or why the connection failed.
 *
 * @field response {http.BytesResponse} the response, any status; empty when `failed`
 * @field failed {bool} whether no response came because the connection was refused or reset
 * @field why {string} the connection's error, cleaned; `""` when not `failed`
 */
def struct Attempt {
    response as http.BytesResponse,
    failed as bool,
    why as string
};

/**
 * Send one attempt of a request within the deadline. A connection the
 * network layer refused or reset (an error of no kind of its own) is
 * returned as `failed`, to be retried; a deadline, a cap, a reply cut off
 * mid-way (kind "closed") and a malformed reply (kind "http") are thrown.
 *
 * @param c {Client} the client
 * @param method {string} the HTTP method
 * @param url {string} the URL
 * @param body {string} a JSON body, `""` for none
 * @param what {string} the request, for messages
 * @return {Attempt} the response or the failure
 */
func exchange(c as Client, method as string, url as string, body as string, what as string) {
    def headers as map of string to string init headersOf($c, $body != "");
    def timeoutMs as int init $c.timeoutMs;
    def maxBytes as int init $c.maxBytes;
    def tls as http.TlsOptions init $c.tls;
    def t as task of http.BytesResponse init spawn {
        return http.requestWithBytes($method, $url, $headers, $body, $timeoutMs, $maxBytes, $tls);
    };
    def none as http.BytesResponse;
    try {
        return Attempt{response: task.waitTimeout($t, $timeoutMs), failed: false, why: ""};
    } catch (e) {
        if ($e.kind == "cancelled") {
            task.cancel($t);
            task.discard($t);
            throw $e;
        }
        if ($e.kind == "timeout") {
            task.cancel($t);
            task.discard($t);
            throw Error{
                kind: "timeout",
                message: io.sprintf("openai: %s: no reply within %d ms", $what, $timeoutMs)
            };
        }
        if ($e.kind == "limit") {
            failLimit(io.sprintf("%s: the reply is over %d bytes", $what, $maxBytes));
        }
        if ($e.kind == "closed") {
            throw Error{
                kind: "closed",
                message: "openai: " + $what + ": the server closed the connection: " +
                    cleaned($e.message, 300)
            };
        }
        if ($e.kind == "http") {
            fail($what + ": " + shown($c.baseUrl) + " sent no valid reply: " +
                cleaned($e.message, 300));
        }
        # the network layer's own errors (kind "runtime"): refused, reset
        return Attempt{response: $none, failed: true, why: cleaned($e.message, 300)};
    }
}

/**
 * Send a request, retry a failed attempt (408, 409, 429, 5xx, a connection
 * refused or reset), and read the JSON reply. A reply cut off mid-way is
 * never retried: the request may have been carried out.
 *
 * @param c {Client} the client
 * @param method {string} the HTTP method
 * @param url {string} the URL
 * @param body {string} a JSON body, `""` for none
 * @param what {string} the request, for messages
 * @return {json.Value} the reply, JSON `null` when it has no body
 */
func send(c as Client, method as string, url as string, body as string, what as string) {
    checkPlain($c);
    def attempt as int init 0;
    while (true) {
        def a as Attempt init exchange($c, $method, $url, $body, $what);
        if ($a.failed) {
            if ($attempt < $c.retries) {
                time.sleep(time.fromMilliseconds(backoff($attempt)));
                $attempt = $attempt + 1;
                continue;
            }
            fail($what + ": cannot reach " + shown($c.baseUrl) + ": " + $a.why);
        }
        def r as http.BytesResponse init $a.response;
        if ($r.status >= 200 and $r.status <= 299) {
            return replyOf($r, $what, $c.apiKey);
        }
        if ($attempt < $c.retries and retryable($r)) {
            def wait as int init retryWait($r, $attempt);
            if ($wait >= 0) {
                time.sleep(time.fromMilliseconds($wait));
                $attempt = $attempt + 1;
                continue;
            }
        }
        failStatus($r, $what, $c.apiKey);
    }
    return json.decode("null");
}

/**
 * Whether a refused request is worth another attempt: a 408, 409, 429 or
 * 5xx the server did not mark `x-should-retry: false`, and not a quota
 * that is used up.
 *
 * @param r {http.BytesResponse} the response
 * @return {bool} true to retry
 */
func retryable(r as http.BytesResponse) {
    if ($r.status != 408 and $r.status != 409 and $r.status != 429 and
        ($r.status < 500 or $r.status > 599)) {
        return false;
    }
    if (maps.has($r.headers, "x-should-retry") and
        strings.lower(strings.trim($r.headers["x-should-retry"])) == "false") {
        return false;
    }
    def e as OpenaiError init errorOf($r, "", "");
    return $e.type != "insufficient_quota" and $e.code != "insufficient_quota";
}

/**
 * How long to wait before the next attempt: the wait the server named
 * (`namedWait`), else `backoff`.
 *
 * @param r {http.BytesResponse} the refused response
 * @param attempt {int} the attempts retried so far
 * @return {int} milliseconds, or -1 when the server asks for more than a minute
 */
func retryWait(r as http.BytesResponse, attempt as int) {
    def asked as int init namedWait($r.headers);
    if ($asked > MAX_RETRY_WAIT_MS) {
        return -1;
    }
    if ($asked >= 0) {
        return $asked;
    }
    return backoff($attempt);
}

/**
 * The wait before a retry the server named none for: 500 ms doubled per
 * attempt, up to 8 s.
 *
 * @param attempt {int} the attempts retried so far
 * @return {int} milliseconds
 */
func backoff(attempt as int) {
    def wait as int init BACKOFF_MS;
    for (def i in 0..$attempt) {
        if ($wait < MAX_BACKOFF_MS) {
            $wait = $wait * 2;
        }
    }
    if ($wait > MAX_BACKOFF_MS) {
        $wait = MAX_BACKOFF_MS;
    }
    return $wait;
}

/**
 * The wait a response names: `retry-after-ms`, else `retry-after` in
 * seconds or as an HTTP date (`Wed, 21 Oct 2026 07:28:00 GMT`; a date
 * passed is 0).
 *
 * @param headers {map of string to string} the response's headers
 * @return {int} milliseconds, at most MAX_NAMED_WAIT_MS; -1 when it names none or a malformed one
 */
func namedWait(headers as map of string to string) {
    def asked as int init -1;
    if (maps.has($headers, "retry-after-ms")) {
        $asked = waitOf(strings.trim($headers["retry-after-ms"]), 1);
    }
    if ($asked < 0 and maps.has($headers, "retry-after")) {
        def value as string init strings.trim($headers["retry-after"]);
        $asked = waitOf($value, 1000);
        if ($asked < 0) {
            $asked = dateWait($value);
        }
    }
    return $asked;
}

/**
 * A retry header's wait in milliseconds.
 *
 * @param value {string} the header: digits, with an optional fraction
 * @param unit {int} milliseconds per unit: 1 or 1000
 * @return {int} the wait, at most MAX_NAMED_WAIT_MS; -1 when the value is not a number
 */
func waitOf(value as string, unit as int) {
    def m as regex.Match init regex.find('^([0-9]+)(\.[0-9]+)?$', $value);
    if ($m.start < 0) {
        return -1;
    }
    if (len($m.groups[0]) > 13) {
        return MAX_NAMED_WAIT_MS;
    }
    def ms as float init convert.toFloat($value) * convert.toFloat($unit);
    if ($ms > convert.toFloat(MAX_NAMED_WAIT_MS)) {
        return MAX_NAMED_WAIT_MS;
    }
    return convert.toInt($ms);
}

/**
 * The wait until an HTTP date (RFC 9110 IMF-fixdate).
 *
 * @param value {string} the date, such as `Wed, 21 Oct 2026 07:28:00 GMT`
 * @return {int} milliseconds from now, 0 for a date passed, at most MAX_NAMED_WAIT_MS; -1 when it is not such a date
 */
func dateWait(value as string) {
    if (not regex.matches(
        '^[A-Za-z]{3}, [0-9]{2} [A-Za-z]{3} [0-9]{4} [0-9]{2}:[0-9]{2}:[0-9]{2} GMT$',
        $value)) {
        return -1;
    }
    def at as int init 0;
    try {
        $at = time.unixMillis(time.parse($value[..len($value) - 4], "%a, %d %b %Y %H:%M:%S"));
    } catch (e) {
        if (lists.contains(GENERIC_KINDS, $e.kind)) {
            throw $e;
        }
        return -1;
    }
    def wait as int init $at - time.unixMillis(time.now());
    if ($wait < 0) {
        return 0;
    }
    if ($wait > MAX_NAMED_WAIT_MS) {
        return MAX_NAMED_WAIT_MS;
    }
    return $wait;
}

/**
 * A 2xx reply as JSON. A reply holding an `error` object is refused even
 * on a 2xx, as some proxies send them.
 *
 * @param r {http.BytesResponse} the response
 * @param what {string} the request, for messages
 * @param key {string} the client's API key, masked in a message
 * @return {json.Value} the reply, JSON `null` when empty
 */
func replyOf(r as http.BytesResponse, what as string, key as string) {
    def text as string init "";
    try {
        $text = convert.stringFromBytes("utf-8", $r.body);
    } catch (e) {
        fail($what + ": the reply is not UTF-8");
    }
    if (strings.trim($text) == "") {
        return json.decode("null");
    }
    def v as json.Value;
    try {
        $v = json.decode($text);
    } catch (e) {
        fail($what + ": the reply is not JSON: " + shown(unkeyed($text, $key)));
    }
    if (json.typeOf($v, "/error") == "map") {
        failStatus($r, $what, $key);
    }
    return $v;
}

/**
 * The error a refused request carries: OpenAI's `{"error": {message, type,
 * param, code}}`, the variants of other servers (`code` a number,
 * `{"error": "text"}`, a top-level `message` or `detail`), or plain text.
 * An HTML page gives only the status text.
 *
 * @param r {http.BytesResponse} the response
 * @param what {string} the request, for the message
 * @param key {string} the client's API key, masked in the server's text
 * @return {OpenaiError} the error
 */
func errorOf(r as http.BytesResponse, what as string, key as string) {
    def e as OpenaiError init OpenaiError{
        kind: "openai",
        message: "",
        status: $r.status,
        type: "",
        code: "",
        param: "",
        requestId: "",
        retryAfterMs: 0,
        limits: {}
    };
    for (def h in ["x-request-id", "apim-request-id"]) {
        if ($e.requestId == "" and maps.has($r.headers, $h)) {
            $e.requestId = cleaned(strings.trim($r.headers[$h]), 100);
        }
    }
    def wait as int init namedWait($r.headers);
    if ($wait > 0) {
        $e.retryAfterMs = $wait;
    }
    for (def k in $r.headers) {
        def lk as string init strings.lower($k);
        if (len($e.limits) < MAX_LIMIT_HEADERS and
            (strings.startsWith($lk, "x-ratelimit-") or $lk == "retry-after" or
            $lk == "retry-after-ms")) {
            $e.limits[$lk] = cleaned(strings.trim($r.headers[$k]), 200);
        }
    }
    def why as string init $r.statusText;
    def text as string init "";
    try {
        $text = unkeyed(strings.trim(convert.stringFromBytes("utf-8", $r.body)), $key);
    } catch (err) {
        $text = "";
    }
    if (strings.startsWith($text, '{')) {
        def v as json.Value;
        def decoded as bool init true;
        try {
            $v = json.decode($text);
        } catch (err) {
            $decoded = false;
        }
        if ($decoded) {
            $e = fieldsOf($e, $v);
            if ($e.message != "") {
                $why = $e.message;
            }
        } else {
            $why = $why + ": " + $text;
        }
    } elseif ($text != "" and not strings.startsWith($text, "<")) {
        $why = $text;
    }
    def detail as list of string init [io.sprintf("HTTP %d", $r.status)];
    if ($e.type != "") {
        $detail[] = "type " + $e.type;
    }
    if ($e.code != "") {
        $detail[] = "code " + $e.code;
    }
    $e.message = "openai: " + $what + ": " + cleaned($why, 500) + " (" +
        strings.join($detail, ", ") +
        ")";
    return $e;
}

/**
 * The fields of a JSON error body: `type`, `code` and `param` set, the
 * server's explanation as `message` (`""` when it gives none).
 *
 * @param e {OpenaiError} the error so far
 * @param v {json.Value} the body
 * @return {OpenaiError} the error
 */
func fieldsOf(e as OpenaiError, v as json.Value) {
    $e.message = "";
    if (json.typeOf($v, "/error") == "string") {
        $e.message = json.asString($v, "/error");
        return $e;
    }
    if (json.typeOf($v, "/detail") == "string") {
        $e.message = json.asString($v, "/detail");
        return $e;
    }
    def at as string init "";
    if (json.typeOf($v, "/error") == "map") {
        $at = "/error";
    } elseif (json.typeOf($v, "/message") != "string") {
        return $e;
    }
    if (json.typeOf($v, $at + "/message") == "string") {
        $e.message = json.asString($v, $at + "/message");
    }
    $e.type = cleaned(scalarAt($v, $at + "/type"), 100);
    $e.code = cleaned(scalarAt($v, $at + "/code"), 100);
    $e.param = cleaned(scalarAt($v, $at + "/param"), 100);
    return $e;
}

/**
 * Throw the OpenaiError of a refused request.
 *
 * @param r {http.BytesResponse} the response
 * @param what {string} the request, for the message
 * @param key {string} the client's API key, masked in the server's text
 * @throws {OpenaiError} kind "openai", always
 */
func failStatus(r as http.BytesResponse, what as string, key as string) {
    throw errorOf($r, $what, $key);
}

/**
 * A string or number at a JSON pointer as text, `""` when absent, null or
 * another type.
 *
 * @param v {json.Value} the document
 * @param ptr {string} the pointer
 * @return {string} the text
 */
func scalarAt(v as json.Value, ptr as string) {
    match (json.typeOf($v, $ptr)) {
        when "string" { return json.asString($v, $ptr); }
        when "int" { return convert.toString(json.asInt($v, $ptr)); }
        else { return ""; }
    }
}

/**
 * A string at a JSON pointer, `""` when absent or null.
 *
 * @param v {json.Value} the document
 * @param ptr {string} the pointer
 * @param what {string} the request, for messages
 * @return {string} the string
 */
func textAt(v as json.Value, ptr as string, what as string) {
    def t as string init json.typeOf($v, $ptr);
    if ($t == "missing" or $t == "null") {
        return "";
    }
    if ($t != "string") {
        fail($what + ": " + shown($ptr) + " is a " + $t + ", not a string");
    }
    return json.asString($v, $ptr);
}

/**
 * An integer at a JSON pointer, 0 when absent or null.
 *
 * @param v {json.Value} the document
 * @param ptr {string} the pointer
 * @param what {string} the request, for messages
 * @return {int} the number
 */
func intAt(v as json.Value, ptr as string, what as string) {
    def t as string init json.typeOf($v, $ptr);
    if ($t == "missing" or $t == "null") {
        return 0;
    }
    if ($t != "int") {
        fail($what + ": " + shown($ptr) + " is a " + $t + ", not an integer");
    }
    return json.asInt($v, $ptr);
}

/**
 * Refuse a reply whose value at a pointer is not a JSON list.
 *
 * @param v {json.Value} the reply
 * @param ptr {string} the pointer
 * @param what {string} the request, for messages
 * @return {int} the list's length
 */
func listAt(v as json.Value, ptr as string, what as string) {
    def t as string init json.typeOf($v, $ptr);
    if ($t != "list") {
        fail($what + ": the reply's " + shown($ptr) + " is " + $t + ", not a list");
    }
    return json.length($v, $ptr);
}

/**
 * A model the server offers.
 *
 * @field id {string} the id a request names, such as `gpt-5.4-mini` or `qwen2.5:0.5b`
 * @field created {int} when it was created, Unix seconds; 0 when the server does not say
 * @field ownedBy {string} who owns it, such as `openai`, `system` or `library`; `""` when the server does not say
 */
export def struct Model {
    id as string,
    created as int,
    ownedBy as string
};

/**
 * The models the server offers (`GET /models`). An `azureVersioned`
 * client lists the resource's models, not its deployments.
 *
 * @param c {Client} the client
 * @return {list of Model} the models, in the server's order
 * @throws {OpenaiError} when the server refuses or sends something else
 * @example
 *   for (def m in openai.models($c)) {
 *       io.printf("%s\n", $m.id);
 *   }
 */
export func models(c as Client) {
    def what as string init "models";
    def v as json.Value init send($c, "GET", urlOf($c, "/models", ""), "", $what);
    def out as list of Model init [];
    for (def i in 0..listAt($v, "/data", $what)) {
        def at as string init "/data/" + convert.toString($i);
        def m as Model init Model{
            id: textAt($v, $at + "/id", $what),
            created: intAt($v, $at + "/created", $what),
            ownedBy: textAt($v, $at + "/owned_by", $what)
        };
        if ($m.created == 0) {
            $m.created = intAt($v, $at + "/created_at", $what);
        }
        if ($m.id == "") {
            fail($what + ": the reply's model " + convert.toString($i) + " has no id");
        }
        $out[] = $m;
    }
    return $out;
}

/**
 * Any other request: `GET /models/gpt-5.4-mini`, `POST /moderations`,
 * `GET /chat/completions/<id>` for a stored completion, an Azure or
 * provider extension. Retries, the deadline, the cap and errors work as for
 * every other request. An `azureVersioned` client puts `/openai` before the
 * path and adds the `api-version`.
 *
 * @param c {Client} the client
 * @param method {string} `GET`, `POST`, `PUT`, `PATCH` or `DELETE`
 * @param path {string} the path below the base URL, starting with `/`, with an optional query
 * @param body {json.Value} the JSON body; JSON `null` for none
 * @return {json.Value} the reply, JSON `null` when it has no body
 * @throws {OpenaiError} when the path is malformed or the server refuses
 * @example
 *   def m as json.Value init openai.call($c, "GET", "/models/gpt-5.4-mini", json.decode("null"));
 */
export func call(c as Client, method as string, path as string, body as json.Value) {
    if (not lists.contains(["GET", "POST", "PUT", "PATCH", "DELETE"], $method)) {
        fail("call: the method is GET, POST, PUT, PATCH or DELETE, got " + shown($method));
    }
    if (not strings.startsWith($path, "/") or strings.startsWith($path, "//") or
        regex.matches('(^|/)(\.|%2[eE]){1,2}(/|$|\?)|[\x00-\x20\x7f#\\]', $path)) {
        fail("call: the path starts with one /, without . or .. segments (also as %2e), spaces, control characters, # or \\, got " +
            shown($path));
    }
    def text as string init "";
    if (not json.isNull($body)) {
        $text = json.encode($body);
    }
    return send($c, $method, urlOf($c, $path, ""), $text, "call " + $method + " " + shown($path));
}
