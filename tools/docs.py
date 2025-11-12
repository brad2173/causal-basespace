

import os
import argparse
import base64
try:
    from dotenv import load_dotenv
except ImportError:
    load_dotenv = None

def load_env_if_exists():
    """Load environment variables from .env if the file exists."""
    env_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), '.env')
    if os.path.exists(env_path) and load_dotenv:
        load_dotenv(env_path)
    elif os.path.exists(env_path):
        print("[WARNING] python-dotenv is not installed. .env file will not be loaded.")



from openai import AzureOpenAI
from azure.identity import DefaultAzureCredential, get_bearer_token_provider
import requests
from bs4 import BeautifulSoup
from prompt_toolkit import PromptSession
from prompt_toolkit.history import InMemoryHistory
from rich.console import Console
from rich.markdown import Markdown


DOCS_URL = "https://developer.basespace.illumina.com/docs/content/documentation/cli/cli-overview"



def fetch_docs(url=DOCS_URL):
	"""Fetch the documentation page HTML."""
	response = requests.get(url)
	response.raise_for_status()
	return response.text

def parse_docs(html):
	"""Parse the documentation HTML and extract main content."""
	soup = BeautifulSoup(html, "html.parser")
	main_content = soup.find("main") or soup.body
	return main_content.get_text(separator="\n", strip=True)

def main():
	load_env_if_exists()
	parser = argparse.ArgumentParser(description="Document Agent for BaseSpace CLI Docs (Azure Entra Auth)")
	parser.add_argument('--question', type=str, help='Ask a question about the documentation')
	parser.add_argument('--shell', action='store_true', help='Start interactive chatbot shell')
	args = parser.parse_args()

	html = fetch_docs()
	content = parse_docs(html)

	if args.question:
		answer = ask_question(content, args.question)
		print(f"Q: {args.question}\nA: {answer}")
	elif args.shell:
		run_shell(content)
	else:
		print("\n--- BaseSpace CLI Documentation Preview ---\n")
		print(content[:1000])  # Print first 1000 chars for preview
		print("\n--- Usage ---")
		print("To ask a question about the documentation, run:")
		print("  python docs.py --question 'Your question here'")
		print("To start the interactive chatbot shell, run:")
		print("  python docs.py --shell")
		print("\nThis script fetches and parses the BaseSpace CLI documentation and can answer questions using Azure OpenAI with Entra ID authentication if the --question argument is provided.")


def run_shell(context):
	console = Console(force_terminal=True)
	session = PromptSession(history=InMemoryHistory())
	# Diagnostic: print Rich color support and a plain ANSI color test
	console.print("[bold green]BaseSpace CLI Chatbot Shell[/bold green] (type 'exit' or Ctrl-D to quit)")
	console.print(f"[dim]Rich color system: {console.color_system}, is_terminal: {console.is_terminal}\n[/dim]")
	print("\033[34mThis is a plain ANSI blue test.\033[0m")
	while True:
		try:
			user_input = session.prompt("[bold blue]You:[/bold blue] ", multiline=True)
		except (EOFError, KeyboardInterrupt):
			console.print("\n[bold yellow]Exiting chat shell.[/bold yellow]")
			break
		if user_input.strip().lower() in {"exit", "quit"}:
			console.print("[bold yellow]Goodbye![/bold yellow]")
			break
		answer = ask_question(context, user_input)
		console.print("[bold magenta]Bot:[/bold magenta]")
		if answer.strip().startswith("[ERROR]"):
			console.print(f"[red]{answer}[/red]")
		else:
			# Render markdown/code blocks if present
			console.print(Markdown(answer))


def ask_question(context, question):
	"""Use Azure OpenAI with Entra ID authentication to answer a question about the documentation."""
	endpoint = os.getenv("ENDPOINT_URL", "https://brad-leblanc-foundry.openai.azure.com/")
	deployment = os.getenv("DEPLOYMENT_NAME", "gpt-4.1")
	api_version = os.getenv("API_VERSION", "2025-01-01-preview")

	try:
		token_provider = get_bearer_token_provider(
			DefaultAzureCredential(),
			"https://cognitiveservices.azure.com/.default"
		)
		client = AzureOpenAI(
			azure_endpoint=endpoint,
			azure_ad_token_provider=token_provider,
			api_version=api_version,
		)
	except Exception as e:
		return f"[ERROR] Failed to initialize Azure OpenAI client: {e}"

	chat_prompt = [
		{
			"role": "system",
			"content": [
				{"type": "text", "text": "You are a helpful assistant. Use the following documentation to answer the user's question. If the answer is not in the documentation, say you don't know."}
			]
		},
		{
			"role": "user",
			"content": [
				{"type": "text", "text": f"Documentation:\n{context}\n\nQuestion: {question}"}
			]
		}
	]

	try:
		completion = client.chat.completions.create(
			model=deployment,
			messages=chat_prompt,
			max_tokens=500,
			temperature=0.2,
			top_p=0.95,
			frequency_penalty=0,
			presence_penalty=0,
			stop=None,
			stream=False
		)
		return completion.choices[0].message.content.strip()
	except Exception as e:
		return f"[ERROR] Failed to get response from Azure OpenAI: {e}"

if __name__ == "__main__":
	main()
