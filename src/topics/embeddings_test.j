# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# openai - white-box tests for the embeddings topic. Spliced into
# openai_test.j via include.

func testEmbeddingsAsSent() {
    def f as Fake init startFake({"POST /v1/embeddings": answer(200, EMBED_DOCS)});
    def req as json.Value init json.decode(
        '{"model": "text-embedding-3-small", "input": "The food was delicious", "dimensions": 3}');
    def reply as json.Value init embeddings(fakeClient($f), $req);
    def seen as list of string init stopFake($f);
    testing.assertEqual(bodyOf($seen[0]), $req);
    testing.assertEqual(vectors($reply), [[0.0023064255, -0.009327292, -0.0028842222]]);
    testing.assertEqual(usage($reply).inputTokens, 8);
}

func testEmbedReadsBase64() {
    def f as Fake init startFake({"POST /v1/embeddings": answer(200, EMBED64_OLLAMA)});
    def vs as list of list of float init embed(fakeClient($f), "all-minilm", ["hello"]);
    def seen as list of string init stopFake($f);
    testing.assertEqual(
        json.encode(bodyOf($seen[0])),
        '{"model":"all-minilm","input":["hello"],"encoding_format":"base64"}');
    testing.assertEqual(len($vs), 1);
    testing.assertEqual(len($vs[0]), 384);
    testing.assertEqual($vs[0][0], -0.06287935376167297);
    testing.assertEqual($vs[0][383], 0.007154644001275301);
}

func testEmbedChecksTheCount() {
    def f as Fake init startFake({"POST /v1/embeddings": answer(200, EMBED_DOCS)});
    def c as Client init fakeClient($f);
    try {
        embed($c, "m", ["a", "b"]);
        missed("one vector for two inputs");
    } catch (e) {
        testing.assertContains($e.message, "embed: 2 inputs gave 1 vectors");
    }
    stopFake($f);
    def many as list of string init [];
    for (def i in 0..MAX_INPUTS + 1) {
        $many[] = "x";
    }
    for (def bad in [[], ["a", ""], $many]) {
        try {
            embed($c, "m", $bad);
            missed(convert.toString(len($bad)));
        } catch (e) {
            testing.assertEqual($e.kind, "openai");
            testing.assertEqual($e.status, 0);
        }
    }
    try {
        embeddings($c, json.decode('{"input": "x"}'));
        missed("no model");
    } catch (e) {
        testing.assertContains($e.message, "naming a model");
    }
}

func testVectorsInIndexOrder() {
    testing.assertEqual(vectors(json.decode(EMBED_SWAPPED)), [[1.0, 1.5], [2.0, 2.5]]);
    for (def bad in [
        '{"data": [{"embedding": [1.0], "index": 1}]}',
        '{"data": [{"embedding": [1.0], "index": 0}, {"embedding": [2.0], "index": 0}]}',
        '{"data": [{"index": 0}]}',
        '{"data": [{"embedding": "@@@", "index": 0}]}',
        '{"data": [{"embedding": "AAAA", "index": 0}, {"embedding": "AAA=", "index": 1}]}',
        '{"object": "list"}',
        '{"data": [{"embedding": ["a", 1.0], "index": 0}]}',
        '{"data": [{"embedding": [1.0, null], "index": 0}]}',
        '{"data": [{"embedding": [], "index": 0}]}',
        '{"data": [{"embedding": "", "index": 0}]}'
    ]) {
        try {
            vectors(json.decode($bad));
            missed($bad);
        } catch (e) {
            testing.assertEqual($e.kind, "openai");
        }
    }
}
