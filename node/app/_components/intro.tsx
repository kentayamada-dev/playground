import type { JSX } from "react";

const text = {
  center: "center.",
  file: "file.",
  fileName: "page.tsx",
  getStarted: "To get started, edit the",
  headOver: "Looking for a starting point or more instructions? Head over to",
  learning: "Learning",
  orThe: "or the",
  templates: "Templates",
};

export const Intro = (): JSX.Element => (
  <div className="flex flex-col items-center gap-6 text-center sm:items-start sm:text-left">
    <h1 className="max-w-xs text-3xl font-semibold leading-10 tracking-tight text-black dark:text-zinc-50">
      {text.getStarted}{" "}
      <code className="rounded bg-black/[.06] px-1.5 py-0.5 font-mono text-[0.9em] dark:bg-white/[.08]">
        {text.fileName}
      </code>{" "}
      {text.file}
    </h1>
    <p className="max-w-md text-lg leading-8 text-zinc-600 dark:text-zinc-400">
      {text.headOver}{" "}
      <a
        href="https://vercel.com/templates?framework=next.js&utm_source=create-next-app&utm_medium=appdir-template-tw&utm_campaign=create-next-app"
        className="font-medium text-zinc-950 dark:text-zinc-50"
      >
        {text.templates}
      </a>{" "}
      {text.orThe}{" "}
      <a
        href="https://nextjs.org/learn?utm_source=create-next-app&utm_medium=appdir-template-tw&utm_campaign=create-next-app"
        className="font-medium text-zinc-950 dark:text-zinc-50"
      >
        {text.learning}
      </a>{" "}
      {text.center}
    </p>
  </div>
);
