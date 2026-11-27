import { Suspense } from "react";
import { connection } from "next/server";
import styles from "./news.module.css";

type Article = {
  id: number;
  title: string;
  summary: string;
  category: string;
  source: string;
  time: string;
};

// Replace with a real fetch() to a news API when ready.
const articles: Article[] = [
  { id: 1, title: "Global markets rally as inflation cools", summary: "Major indices closed higher after new data showed easing price pressures across several economies.", category: "Business", source: "Market Desk", time: "1h ago" },
  { id: 2, title: "New battery tech promises 2x EV range", summary: "Researchers unveiled a solid-state design that could double driving range while cutting charge times.", category: "Technology", source: "Tech Wire", time: "2h ago" },
  { id: 3, title: "Coastal cities prepare for record storm season", summary: "Officials are upgrading flood defenses and evacuation plans ahead of forecasts for an active season.", category: "World", source: "World Report", time: "3h ago" },
  { id: 4, title: "Local team clinches championship in overtime", summary: "A last-second goal sealed a dramatic win in front of a sold-out crowd.", category: "Sports", source: "Sports Daily", time: "5h ago" },
  { id: 5, title: "Study links short daily walks to better sleep", summary: "A ten-minute walk was associated with measurable improvements in sleep quality, researchers found.", category: "Health", source: "Health Journal", time: "6h ago" },
  { id: 6, title: "Space agency confirms next lunar landing window", summary: "The mission timeline was updated following successful final system tests.", category: "Science", source: "Science Today", time: "8h ago" },
];

async function Today() {
  await connection();
  return <p>{new Date().toLocaleDateString("en-US", { dateStyle: "full" })}</p>;
}

export default function Home() {
  const [lead, ...rest] = articles;
  return (
    <main className={styles.container}>
      <header className={styles.header}>
        <h1>Daily News</h1>
        <Suspense fallback={<p>&nbsp;</p>}>
          <Today />
        </Suspense>
      </header>

      <article className={styles.lead}>
        <span className={styles.tag}>{lead.category}</span>
        <h2>{lead.title}</h2>
        <p>{lead.summary}</p>
        <small>{lead.source} · {lead.time}</small>
      </article>

      <section className={styles.grid}>
        {rest.map((a) => (
          <article key={a.id} className={styles.card}>
            <span className={styles.tag}>{a.category}</span>
            <h3>{a.title}</h3>
            <p>{a.summary}</p>
            <small>{a.source} · {a.time}</small>
          </article>
        ))}
      </section>
    </main>
  );
}
