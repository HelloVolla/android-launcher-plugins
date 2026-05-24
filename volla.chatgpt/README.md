# ChatGPT Plugin for Volla Launcher

This plugin integrates ChatGPT directly into the Volla Launcher springboard, allowing you to ask questions and get AI-powered responses without leaving your home screen.

## Setup

### 1. Get your OpenAI API Key
1. Visit [OpenAI Platform](https://platform.openai.com/api-keys)
2. Sign in or create an account
3. Create a new API key
4. Copy your API key (it starts with `sk-`)

### 2. Configure the Plugin
You can configure your API key in two ways:
- **Set the `apiKey` property** directly in the plugin source (for developers).
- **Let the user set it** via the launcher interface:
  1. Open the Volla Launcher springboard (smart text field)
  2. Type: `chatgpt set key YOUR_API_KEY`
     - Replace `YOUR_API_KEY` with your actual OpenAI API key
  3. Press Enter
  4. You should see a confirmation message

> **Note:** When the user sets the API key through the launcher interface, the property is set for the current session and will be reset when the launcher restarts.  
> **TODO:** Persistently store the API key so it remains set after restarting the launcher.

### Alternative Setup
If you need help with setup, type: `chatgpt setup` in the springboard for detailed instructions.

## Usage

Once configured, you can use any of these trigger words followed by your question:

- `ask [your question]` - Example: `ask What is the capital of France?`
- `gpt [your question]` - Example: `gpt Explain quantum physics`  
- `chat [your question]` - Example: `chat Write a poem about spring`
- `ai [your question]` - Example: `ai Help me plan a dinner party`

## Features

- **Easy Setup**: Configure your API key directly through the launcher interface
- **Multiple Triggers**: Use `ask`, `gpt`, `chat`, or `ai` to activate
- **Error Handling**: Clear error messages for common issues
- **Rate Limiting**: Handles OpenAI rate limits gracefully
- **Debounce Mechanism**: ChatGPT requests are only sent after you have stopped typing for 2 seconds, reducing unnecessary API calls.

## Commands

- `chatgpt setup` - Show setup instructions
- `chatgpt help` - Show help information  
- `chatgpt config` - Show configuration options
- `chatgpt set key [API_KEY]` - Set your OpenAI API key

## Troubleshooting

### "API key not configured" errorapiKey
- Make sure you've set your API key using `chatgpt set key YOUR_API_KEY`
- Verify your API key is valid and starts with `sk-`

### "Invalid API key" error  
- Double-check your API key is correct
- Ensure you have sufficient credits in your OpenAI account
- Try setting the key again: `chatgpt set key YOUR_API_KEY`

### "Rate limit exceeded" error
- You've made too many requests in a short time
- Wait a few minutes and try again
- Consider upgrading your OpenAI plan for higher limits
