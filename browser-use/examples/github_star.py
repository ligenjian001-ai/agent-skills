#!/usr/bin/env python3
import asyncio
import os

for var in ["GOOGLE_GEMINI_BASE_URL", "GEMINI_API_KEY"]:
    os.environ.pop(var, None)

from browser_use import Agent, Browser, ChatGoogle

async def main():
    task_instruction = "Go to https://github.com/browser-use/browser-use and extract the exact number of stars the repository has. Print just the number."
    
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
    
    # Close browser cleanly to avoid hanging processed
    await browser.close()

if __name__ == "__main__":
    asyncio.run(main())
