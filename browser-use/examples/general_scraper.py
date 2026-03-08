#!/usr/bin/env python3
import asyncio
import os
import argparse

for var in ["GOOGLE_GEMINI_BASE_URL", "GEMINI_API_KEY"]:
    os.environ.pop(var, None)

from browser_use import Agent, Browser, ChatGoogle

async def main(url, target_info):
    task_instruction = f"Navigate to {url} and extract information about: {target_info}. Present the findings clearly."
    
    if not os.getenv("GOOGLE_API_KEY"):
        raise ValueError("GOOGLE_API_KEY environment variable is not set")

    llm = ChatGoogle(
        model="gemini-2.5-flash",
        api_key=os.getenv("GOOGLE_API_KEY")
    )
    
    browser = Browser(headless=True)
    agent = Agent(task=task_instruction, llm=llm, browser=browser)
    
    print(f"Task: {task_instruction}")
    result = await agent.run()
    
    print("\n=== Extracted Result ===")
    print(result)
    
    await browser.close()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="A generic webpage scraper example")
    parser.add_argument("--url", default="https://example.com", help="Target URL")
    parser.add_argument("--info", default="the main heading and purpose of the page", help="What to extract")
    args = parser.parse_args()
    
    asyncio.run(main(args.url, args.info))
