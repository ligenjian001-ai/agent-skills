#!/usr/bin/env python3
import asyncio
import argparse
import os

# 清除 AG 代理环境变量, 确保直连 Gemini API
for var in ["GOOGLE_GEMINI_BASE_URL", "GEMINI_API_KEY"]:
    os.environ.pop(var, None)

from browser_use import Agent, Browser, ChatGoogle

async def run_task(task_instruction):
    if not os.getenv("GOOGLE_API_KEY"):
        raise ValueError("GOOGLE_API_KEY environment variable is not set")

    # Connect to Gemini 2.5 Flash via browser-use's ChatGoogle
    llm = ChatGoogle(
        model="gemini-2.5-flash",
        api_key=os.getenv("GOOGLE_API_KEY")
    )
    
    # We create a browser explicitly in headless mode
    browser = Browser(headless=True)
    
    agent = Agent(
        task=task_instruction,
        llm=llm,
        browser=browser
    )
    
    print(f"Starting browser-use agent with task: {task_instruction}")
    result = await agent.run()
    
    print("\n=== Task Result ===")
    print(result)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run a browser-use task via Gemini 2.5 Flash")
    parser.add_argument("--task", required=True, help="Task instruction in natural language")
    args = parser.parse_args()
    
    asyncio.run(run_task(args.task))
