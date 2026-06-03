overview: https://docs.google.com/presentation/d/1Am5adKxpMCp9yE9u1n5Sr_6yfHISk_401i9V8wRkV94/edit?usp=sharing


current impl features: (macOS)
- cmd + option + t : toggles chat bar on/off
- ctrl + option + arrow (up/down/left/right) : moves chat bar some pixel amount in x direction
- uses an OpenRouter multimodal model (OpenAI-compatible) for chat — handles both text and images
- attach images (paperclip button or drag/drop) and ask about them — the model sees the image and answers, keeping it in context for follow-ups
- ability to start focus session by typing "start focus session" into chat bar

setup: put your OpenRouter key in `~/.config/poro/env` as `OPENROUTER_API_KEY=...` (free key at https://openrouter.ai/keys). The build bundles that file via the `Poro/Poro.env` symlink. See CLAUDE.md for details.

Focus session
- grabs info regarding focused tabs; passes to LLM to check if focused tab is related to designated focus session task
- if LLM returns confidence threshold above 0.75, will trigger an event giving user 10 seconds with two choices
  - user can close tab
  - user can justify why they have this tab open (i.e break/emergency)
- else
  - if no response within 10s, tab will auto close 
