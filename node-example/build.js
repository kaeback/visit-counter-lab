// src/index.md(마크다운)를 HTML로 바꿔 dist/index.html 을 만든다
const fs = require("fs");
const { marked } = require("marked");

const md = fs.readFileSync("src/index.md", "utf8");
fs.mkdirSync("dist", { recursive: true });
fs.writeFileSync("dist/index.html",
  `<!doctype html><meta charset="utf-8"><title>node-example</title>\n${marked.parse(md)}`);
console.log("dist/index.html 생성");
