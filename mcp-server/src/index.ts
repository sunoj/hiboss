#!/usr/bin/env node
// Starts the hiboss MCP stdio server and wires MCP tools to hiboss APIs.
// Imports configuration, transports, and tool registration from helper modules.
// Depends on @modelcontextprotocol/sdk and Node stdlib utilities.

import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { loadHibossContext } from './context.js';
import { registerTools } from './tools.js';
import { startBackgroundListener } from './listener.js';
import { getErrorMessage } from './format.js';

const MCP_VERSION = '0.1.0';

async function main() {
  const context = await loadHibossContext();
  const server = new McpServer(
    { name: 'hiboss-mcp-server', version: MCP_VERSION },
    { capabilities: { logging: {} } },
  );
  registerTools(server, context);
  const transport = new StdioServerTransport();
  transport.onclose = () => {
    void server.close();
  };
  await server.connect(transport);
  startBackgroundListener(server, context);
}

main().catch((error) => {
  console.error('hiboss MCP server failed:', getErrorMessage(error));
  process.exit(1);
});
