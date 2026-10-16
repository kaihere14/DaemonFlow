import { About } from "@/components/About";
import { Faq } from "@/components/Faq";
import { Features } from "@/components/Features";
import { Footer } from "@/components/Footer";
import { Hero } from "@/components/Hero";
import { Note } from "@/components/Note";
import { Pricing } from "@/components/Pricing";

export default function Home() {
  return (
    <>
      <Hero />
      <main>
        <Features />
        <Note />
        <About />
        <Pricing />
        <Faq />
      </main>
      <Footer />
    </>
  );
}
