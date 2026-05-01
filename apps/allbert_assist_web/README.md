# AllbertAssistWeb

Phoenix web surface for Allbert Assist.

Start the web demo:

```sh
export ALLBERT_MEMORY_ROOT=/tmp/allbert-v001-demo
export ALLBERT_TRACE_ENABLED=true
mix phx.server
```

Open `http://localhost:4000/agent`.

The `/agent` LiveView uses the same `AllbertAssist.Runtime.submit_user_input/1`
boundary as the CLI and displays response status, signal id, and trace path
when tracing is enabled.
