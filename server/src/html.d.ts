// Type declaration for importing .html files as text modules (Wrangler Text rules).

declare module '*.html' {
  const content: string;
  export default content;
}
