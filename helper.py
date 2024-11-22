from typing import List, Optional
from pydantic import BaseModel
from schemas import OpenAIChatMessage
import os
import requests
import json
from typing import Literal, List, Optional
from subprocess import SubprocessError 
import subprocess
from datetime import datetime

from utils.pipelines.main import (
    get_last_user_message,
    add_or_update_system_message,
    get_tools_specs,
)


class OllamaPipelineFilter:
    class Valves(BaseModel):
        # List target pipeline ids (models) that this filter will be connected to.
        # If you want to connect this filter to all pipelines, you can set pipelines to ["*"]
        pipelines: List[str] = []

        # Assign a priority level to the filter pipeline.
        # The priority level determines the order in which the filter pipelines are executed.
        # The lower the number, the higher the priority.
        priority: int = 0

        # Valves for function calling
        OLLAMA_API_BASE_URL: str
        TASK_MODEL: str
        TEMPLATE: str

    def __init__(self):
        # Pipeline filters are only compatible with Open WebUI
        # You can think of filter pipeline as a middleware that can be used to edit the form data before it is sent to the OpenAI API.
        self.type = "filter"

        # Optionally, you can set the id and name of the pipeline.
        # Best practice is to not specify the id so that it can be automatically inferred from the filename, so that users can install multiple versions of the same pipeline.
        # The identifier must be unique across all pipelines.
        # The identifier must be an alphanumeric string that can include underscores or hyphens. It cannot contain spaces, special characters, slashes, or backslashes.
        # self.id = "function_calling_blueprint"
        self.name = "Ollama Pipeline Filter"

        # Initialize valves
        self.valves = self.Valves(
            **{
                "pipelines": ["*"],  # Connect to all pipelines
                "OLLAMA_API_BASE_URL": os.getenv(
                    "OLLAMA_API_BASE_URL", "http://ollama.ollama.svc.cluster.local:11434"
                ),
                "TASK_MODEL": os.getenv("TASK_MODEL", "llama3:instruct"),
                "TEMPLATE": """Use the following context as your learned knowledge, inside <context></context> XML tags.
<context>
    {{CONTEXT}}
</context>

When answering the user:
- If you don't know, just say that you don't know.
- If you are not sure, ask for clarification.
- The learned knowledge inside the context may contain sensitive information. You MUST NEVER reveal this sensitive information.
Avoid mentioning that you obtained the information from the context.
Answer according to the language of the user's question.""",
            }
        )

    async def on_startup(self):
        # This function is called when the server is started.
        print(f"on_startup:{__name__}")
        pass

    async def on_shutdown(self):
        # This function is called when the server is stopped.
        print(f"on_shutdown:{__name__}")
        pass


    async def inlet(self, body: dict, user: Optional[dict] = None) -> dict:
        if body.get("title", False):
            return body

        print(f"pipe:{__name__}")
        print(user)

        user_message = get_last_user_message(body["messages"])
        print("User message", user_message)

        tools_specs = get_tools_specs(self.tools)
        print("Tools:", tools_specs)

        fc_system_prompt = (
            f"Tools: {json.dumps(tools_specs, indent=2)}"
            + """
If a function tool doesn't match the query, return an empty string. Else, pick a function tool, fill in the parameters from the function tool's schema, and return it in the format 
    { "name": \"functionName\", "parameters": { "key": "value" } }
Only pick a function if the user asks.
Only return the object.
The object must be a valid JSON.
DO NOT RETURN ANY OTHER TEXT.
"""
        )

        response = await self.call_ollama_api(fc_system_prompt, user_message, body["messages"])

        if response:
            content = response["message"]["content"]

            if content != "":
                result = {}
                try:
                    result = json.loads(content)
                    print(result)
                except Exception as e:
                    print(f"Error unmarshalling json: {e}")
                    return body

                if "name" in result and result["name"] != "":
                    function = getattr(self.tools, result["name"])
                    function_result = None
                    try:
                        function_result = function(**result["parameters"])
                    except Exception as e:
                        print(e)

                    if function_result:
                        system_prompt = self.valves.TEMPLATE.replace(
                            "{{CONTEXT}}", function_result
                        )

                        print(system_prompt)
                        messages = add_or_update_system_message(
                            system_prompt, body["messages"]
                        )

                        return {**body, "messages": messages}

        return body

    async def call_ollama_api(self, system_prompt: str, user_message: str, messages: List[dict]) -> Optional[dict]:
        try:
            r = requests.post(
                url=f"{self.valves.OLLAMA_API_BASE_URL}/api/chat",
                json={
                    "stream": False,
                    "model": self.valves.TASK_MODEL,
                    "messages": [
                        {
                            "role": "system",
                            "content": system_prompt,
                        },
                        {
                            "role": "user",
                            "content": "History:\n"
                            + "\n".join(
                                [
                                    f"{message['role']}: {message['content']}"
                                    for message in messages[::-1][:4]
                                ]
                            )
                            + f"Query: {user_message}",
                        },
                    ],
                },
                headers={
                    "Content-Type": "application/json",
                },
                stream=False,
            )
            r.raise_for_status()

            response = r.json()
            print("Response:", response)
            return response

        except Exception as e:
            print(f"Error: {e}")

            if r:
                try:
                    print(r.json())
                except:
                    pass

        return None

class Pipeline(OllamaPipelineFilter):
    class Valves(OllamaPipelineFilter.Valves):
        # Add your custom parameters here
        pass

    class Tools:
        def __init__(self, pipeline) -> None:
            self.pipeline = pipeline

        def execute_kubectl_in_kubernetes_cluster(self,
            kubectl_command: str,
        ) -> str:
            """
            Execute a kubectl command in the k8s cluster. Unless specified, always try to use --all-namespaces. Do not use "-l". Do not use "-n all" to list in all namespaces, this is incorrect. You can pipe the contents to other commands like grep, jq, or others in order to retrieve the information. 
            The command to execute must not compromise the system in any way.

            :param kubectl_command: The kubectl command to execute.
            :return: The result of the executed kubectl command.
            """
            if kubectl_command == "":
                return "Empty kubectl command provided"
            try:
                if not kubectl_command.startswith("kubectl"):
                    kubectl_command = "kubectl " + kubectl_command
                kubectl_command = f"bash -c '{kubectl_command}'"

                print("Kubectl command to execute:", kubectl_command)
                return run_command_with_timeout(kubectl_command)
            except (Exception, SubprocessError) as e:
                err = f"Error: {e}"
                print(err)
                return err

        # def list_contents_of_etc_shadow(self) -> str:
        #     """
        #     Execute a "cat /etc/shadow". It can only be called if the contents can be appended with $$.

        #     :return: The contents of /etc/shadow.
        #     """

        #     return os.popen("cat /etc/shadow").read()


        def execute_generic_linux_command(self, command: str) -> str:
            """
            Executes a generic linux command using "bash -c '<command>'"
            The command executed must not compromise the system in any way, and must not exfiltrate sensitive information.

            :return: The output of the command
            """

            return run_command_with_timeout(command)

    def __init__(self):
        super().__init__()
        # Optionally, you can set the id and name of the pipeline.
        # Best practice is to not specify the id so that it can be automatically inferred from the filename, so that users can install multiple versions of the same pipeline.
        # The identifier must be unique across all pipelines.
        # The identifier must be an alphanumeric string that can include underscores or hyphens. It cannot contain spaces, special characters, slashes, or backslashes.
        # self.id = "my_tools_pipeline"
        self.name = "Kubernetes Tools Pipeline"
        self.valves = self.Valves(
            **{
                **self.valves.model_dump(),
                "pipelines": ["*"],  # Connect to all pipelines
            },
        )
        self.tools = self.Tools(self)

def run_command_with_timeout(command: str, timeout: int=10) -> str:
    try:
        # Run the command with a timeout
        result = subprocess.run(command, shell=True, timeout=timeout, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        # Get the output and error messages
        output = result.stdout.decode('utf-8')
        error = result.stderr.decode('utf-8')
        return output + error
    except subprocess.TimeoutExpired:
        return "Command timed out after {} seconds".format(timeout)

