# Agent rules

## Network

You are running inside a sandboxed container with no direct internet access.
The only outbound route is through a security proxy at `http://pipelock:8888`.

### Fetching web content

Do **not** attempt direct `curl`, `wget`, or `fetch()` to arbitrary URLs —
they will fail. To read a web page, use the pipelock fetch endpoint:

```sh
curl -s "http://pipelock:8888/fetch?url=https://example.com/some/path"
```

The response is JSON of the form:

```json
{
  "url": "...",
  "status_code": 200,
  "content_type": "text/html",
  "title": "...",
  "content": "<extracted readable text>",
  "blocked": false
}
```

Pass an `X-Pipelock-Agent: opencode` header so audit logs are attributed
correctly:

```sh
curl -s -H "X-Pipelock-Agent: opencode" \
  "http://pipelock:8888/fetch?url=$URL"
```

If `blocked` is `true`, do not retry with a different URL trying to evade
the scanner. Tell the user what was blocked and why, and stop.

### Package installation

`npm install`, `bun install`, `pip install`, `cargo add`, and `git clone` of
github.com all work normally — pipelock allowlists those registries. Anything
else will be refused at the proxy.
