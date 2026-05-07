overview: https://docs.google.com/presentation/d/1Am5adKxpMCp9yE9u1n5Sr_6yfHISk_401i9V8wRkV94/edit?usp=sharing


current impl features: (macOS)
- cmd + option + t : toggles chat bar on/off
- ctrl + option + arrow (up/down/left/right) : moves chat bar some pixel amount in x direction
- uses Llama 3.1 powered by Cerebras for chat infra
- ability to start focus session by typing "start focus session" into chat bar

Focus session
- grabs info regarding focused tabs; passes to LLM to check if focused tab is related to designated focus session task
- if LLm returns confidence threshold above 0.75, will trigger an event giving user 10 seconds with two choices
  - user can close tab
  - user can justify why they have this tab open (i.e break/emergency)
- else
  - if no response within 10s, tab will auto close 
