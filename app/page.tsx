import Image from "next/image";

export default function Home() {
  return (
    <div className="flex flex-col flex-1 bg-zinc-950 font-sans text-zinc-100">
      <header className="border-b border-zinc-800 bg-zinc-900/80 backdrop-blur">
        <div className="mx-auto flex max-w-5xl flex-col items-center gap-1 px-6 py-6 text-center sm:flex-row sm:justify-between sm:text-left">
          <h1 className="text-xl font-extrabold tracking-[0.25em] text-white sm:text-2xl">
            TRACK. MANAGE. <span className="text-red-500">RECOVER.</span>
          </h1>
          <p className="text-sm font-medium uppercase tracking-widest text-zinc-400">
            TrackTool Senior Developer
          </p>
        </div>
      </header>

      <main className="flex flex-1 items-center justify-center px-6 py-16">
        <figure className="w-full max-w-4xl">
          <div className="overflow-hidden rounded-2xl shadow-2xl shadow-red-900/20 ring-1 ring-zinc-800">
            <Image
              src="/1970-ford-mustang-fastback.jpeg"
              alt="1970 Ford Mustang Fastback"
              width={1920}
              height={1280}
              loading="eager"
              className="h-auto w-full transition-transform duration-500 hover:scale-105"
            />
          </div>
          <figcaption className="mt-4 text-center text-sm uppercase tracking-widest text-zinc-500">
            1970 Ford Mustang Fastback
          </figcaption>
        </figure>
      </main>
    </div>
  );
}
