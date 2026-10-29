import { Actions } from "./_components/actions";
import Image from "next/image";
import { Intro } from "./_components/intro";
import type { JSX } from "react";

const Home = (): JSX.Element => (
  <div className="flex flex-1 flex-col items-center justify-center bg-zinc-50 font-sans dark:bg-black">
    <main className="flex flex-1 flex-col items-center justify-between bg-white px-16 py-32 inline-full max-inline-3xl sm:items-start dark:bg-black">
      <Image
        className="block-5 inline-25 dark:invert"
        src="/next.svg"
        alt="Next.js logo"
        width={100}
        height={20}
        priority
      />
      <Intro />
      <Actions />
    </main>
  </div>
);

export default Home;
