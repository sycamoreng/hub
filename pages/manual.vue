<script setup lang="ts">
definePageMeta({ title: 'Staff Manual' })

const today = new Date().toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric' })

function printPage() {
  if (typeof window !== 'undefined') window.print()
}

interface Section {
  id: string
  title: string
  intro?: string
  items: { name: string; detail: string }[]
}

const sections: Section[] = [
  {
    id: 'getting-started',
    title: '1. Getting Started',
    intro: 'How to sign in and find your way around the Sycamore Info Hub.',
    items: [
      { name: 'Signing in', detail: 'The hub uses Google single sign-on. On the login screen, tap "Continue with Google" and pick your Sycamore account. Access is limited to @sycamore.ng and @sycamoreglobal.co.uk Google accounts — personal Gmail addresses will be rejected.' },
      { name: 'Your profile', detail: 'Open the Profile page from the sidebar to update your photo, bio and contact details. Department, role and reporting line are synced from Google Workspace by the admin team.' },
      { name: 'Navigation', detail: 'The left sidebar groups pages by theme: Rewards & Play, Company, Productivity, Products & Tech, People & Culture and Communication. Click a group heading to expand it. Your home page shows the Daily Spark and a live feed of company activity.' }
    ]
  },
  {
    id: 'feed',
    title: '2. Feed, Posts and Comments',
    intro: 'Stay in the loop and contribute to the conversation.',
    items: [
      { name: 'Reading the feed', detail: 'The Feed page streams posts from across the company. React with emoji, leave comments, and use @mentions to bring a colleague into the conversation.' },
      { name: 'Creating a post', detail: 'Tap the Post button on the feed. You can pick a template (birthday, anniversary, mood, milestone, kudos, welcome or congrats), attach an image, and tag colleagues with @mentions.' },
      { name: 'Announcements', detail: 'Admins publish company-wide announcements that appear pinned at the top of the feed with their own image and call-to-action.' }
    ]
  },
  {
    id: 'notifications',
    title: '3. Notifications',
    intro: 'Never miss a mention, kudos or approval.',
    items: [
      { name: 'Notifications bell', detail: 'The bell icon in the top bar shows a count of unread notifications. Click it for a dropdown preview, or open the Notifications page for the full history.' },
      { name: 'What you get notified about', detail: 'Mentions on posts and announcements, reactions and comments on your posts, kudos received, badges earned, and leave or finance approvals.' },
      { name: 'Notification settings', detail: 'Open Notification Settings from your profile menu to turn specific categories on or off. You can also unsubscribe from email via the link on any notification email.' }
    ]
  },
  {
    id: 'attendance',
    title: '4. Attendance',
    intro: 'Clock in and out, and view your working time.',
    items: [
      { name: 'Clocking in and out', detail: 'Open the Clock In page from the sidebar and tap Clock In at the start of your shift. Tap Clock Out at the end. A clock-in earns leaderboard points.' },
      { name: 'Schedules', detail: 'If your team uses schedule templates, your expected hours appear on the Attendance page. Talk to your manager or team lead about any changes.' }
    ]
  },
  {
    id: 'leave',
    title: '5. Leave',
    intro: 'Request and manage time off.',
    items: [
      { name: 'Requesting leave', detail: 'On the Leave page, choose a leave type, pick start and end dates (half-days at the start or end are supported), and submit. Your manager is notified automatically.' },
      { name: 'Handover and relief officer', detail: 'Before submitting, nominate a relief officer and write a short handover note. The relief officer receives a notification and can accept or decline the cover.' },
      { name: 'Balances', detail: 'Your remaining allocation per leave type appears at the top of the page. Public holidays and weekends are automatically excluded from working-day calculations.' }
    ]
  },
  {
    id: 'recognition',
    title: '6. Recognition, Kudos and Badges',
    intro: 'Celebrate each other and earn points as you go.',
    items: [
      { name: 'Giving kudos', detail: 'Open Recognition and pick a colleague, choose a kudos value (the available values are curated by admins and appear in the picker), and add a short note. Kudos appear on the public wall.' },
      { name: 'Earning points', detail: 'Posting, commenting, receiving reactions, giving and receiving kudos, completing learning steps, clocking in and answering the Daily Spark all earn points.' },
      { name: 'Badges', detail: 'Badges unlock when you hit milestones — first post, comment streaks, point thresholds and more. Each badge also drops bonus points onto the leaderboard.' },
      { name: 'Leaderboard', detail: 'The Recognition page shows leaders for the week, month and all time. Your position updates live as events are logged.' }
    ]
  },
  {
    id: 'daily-spark',
    title: '7. Daily Spark & Wordle',
    intro: 'Quick daily games that keep the hub lively.',
    items: [
      { name: 'Daily Spark', detail: 'A single multiple-choice question (A/B/C/D) appears on the home page each day. Pick an answer to score — a correct answer earns the full points.' },
      { name: 'Daily Wordle', detail: 'Guess the word of the day within the allowed attempts. A win adds points to your leaderboard total and unlocks streak badges.' }
    ]
  },
  {
    id: 'learning',
    title: '8. Onboarding & Learning',
    intro: 'Ramp up on Sycamore with structured learning paths.',
    items: [
      { name: 'Assigned learning', detail: 'The Onboarding page shows modules assigned to you. Assignments can be organisation-wide, department-specific, or aimed at individual staff — so what you see is tailored to your role.' },
      { name: 'Resources and progress', detail: 'Each step can include a video, document or link. Open the resource, then mark the step complete to earn points and keep your progress bar moving.' }
    ]
  },
  {
    id: 'payroll-finance',
    title: '9. Payroll, Finance & Benefits',
    intro: 'Your pay and benefits, in one place.',
    items: [
      { name: 'Payroll', detail: 'The Payroll page shows your payslips and employee details. Contact the admin team if anything looks off.' },
      { name: 'Advance & Loans', detail: 'Submit advance and loan requests from the Finance page. Attach supporting documents where required; your manager and finance admins will review.' },
      { name: 'Benefits & perks', detail: 'The Benefits page lists every perk the company offers, with eligibility and how to claim.' }
    ]
  },
  {
    id: 'people',
    title: '10. People, Teams & Organogram',
    intro: 'Find colleagues and understand how we are organised.',
    items: [
      { name: 'Staff directory', detail: 'Search the Staff Directory by name, role or department. Click a profile to see contact details and reporting line.' },
      { name: 'My Team and Departments', detail: 'My Team shows your direct reports and peers. Departments lists every department with its head and members. Team leads and heads are highlighted.' },
      { name: 'Leadership and Organogram', detail: 'The Leadership page features the senior team and their focus areas. The Organogram page visualises the full reporting chain.' }
    ]
  },
  {
    id: 'communication',
    title: '11. Communication',
    intro: 'Company-wide messages, chat and the shared calendar.',
    items: [
      { name: 'Communication hub', detail: 'The Communication page collects announcements, broadcasts and key messages in one stream for easy reference.' },
      { name: 'Key contacts & Calendar', detail: 'Key Contacts lists emergency and operational contacts. The Calendar page shows company events, holidays and scheduled activities.' },
      { name: 'AI chat assistant', detail: 'The chat widget (bottom-right on every page) answers questions from the hub\'s own knowledge base — products, policies, benefits, contacts, departments, locations, onboarding, leadership and general company info. It will not answer off-topic questions.' }
    ]
  },
  {
    id: 'admin',
    title: '12. For Admins',
    intro: 'Everything behind the Admin menu.',
    items: [
      { name: 'Company setup', detail: 'Configure company details, locations, departments and leadership from the Admin section.' },
      { name: 'People management', detail: 'Add and edit staff, teams, admins and page access. The Google Sync page imports or refreshes staff from Google Workspace.' },
      { name: 'Content', detail: 'Curate policies, benefits, products, technology, contacts, onboarding modules, learning assignments and email templates.' },
      { name: 'Gamification', detail: 'Adjust point weights, kudos values, badges (including bonus points) and Daily Sparks.' },
      { name: 'Operations', detail: 'Run payroll, approve leave, review finance requests, manage attendance and schedule templates.' },
      { name: 'Integrations', detail: 'Configure Google chat spaces and broadcasts for reaching every channel at once.' }
    ]
  },
  {
    id: 'support',
    title: '13. Getting Help',
    items: [
      { name: 'In-app assistant', detail: 'The chat widget is available on every page. Ask anything about company info — it pulls from policies, benefits, products, technology and contacts.' },
      { name: 'Escalation', detail: 'For anything the assistant cannot resolve, contact your manager, the admin team, or the relevant department head listed on the Departments or Leadership pages.' }
    ]
  }
]
</script>

<template>
  <div class="max-w-5xl mx-auto">
    <div class="flex items-start justify-between gap-4 mb-8 no-print">
      <div>
        <h1 class="section-title">Staff Manual</h1>
        <p class="section-subtitle">Everything you can do in the Sycamore Info Hub, in one place.</p>
      </div>
      <button
        @click="printPage"
        class="inline-flex items-center gap-2 px-4 py-2 rounded-lg bg-sycamore-700 text-white text-sm font-medium hover:bg-sycamore-800 transition-colors"
      >
        Download PDF
      </button>
    </div>

    <article class="manual bg-white border border-slate-200 rounded-2xl p-8 md:p-12 shadow-sm">
      <header class="border-b border-slate-200 pb-8 mb-8">
        <div class="text-xs uppercase tracking-widest text-sycamore-700 font-semibold mb-2">Sycamore Info Hub</div>
        <h2 class="text-4xl font-bold text-slate-900 mb-2">Staff Operating Manual</h2>
        <p class="text-slate-600">A practical guide for everyone at Sycamore — what lives on the hub and how to use it.</p>
        <p class="text-sm text-slate-500 mt-4">Version 1.1 &middot; {{ today }}</p>
      </header>

      <nav class="mb-10 print-toc">
        <h3 class="text-lg font-semibold text-slate-900 mb-3">Contents</h3>
        <ol class="grid md:grid-cols-2 gap-y-2 gap-x-6 text-sm">
          <li v-for="s in sections" :key="s.id">
            <a :href="`#${s.id}`" class="text-sycamore-700 hover:text-sycamore-900 hover:underline">{{ s.title }}</a>
          </li>
        </ol>
      </nav>

      <section
        v-for="s in sections"
        :key="s.id"
        :id="s.id"
        class="mb-10 last:mb-0 section-block"
      >
        <h3 class="text-2xl font-bold text-slate-900 mb-2">{{ s.title }}</h3>
        <p v-if="s.intro" class="text-slate-600 mb-4">{{ s.intro }}</p>
        <dl class="space-y-4">
          <div v-for="item in s.items" :key="item.name" class="border-l-2 border-sycamore-200 pl-4">
            <dt class="font-semibold text-slate-900">{{ item.name }}</dt>
            <dd class="text-slate-700 mt-1 leading-relaxed">{{ item.detail }}</dd>
          </div>
        </dl>
      </section>

      <footer class="border-t border-slate-200 pt-6 mt-10 text-sm text-slate-500">
        <p>For questions or suggested edits, contact the Sycamore admin team through the in-app chat.</p>
      </footer>
    </article>
  </div>
</template>

<style scoped>
.section-title { font-size: 2rem; font-weight: 700; color: rgb(15 23 42); }
.section-subtitle { color: rgb(71 85 105); margin-top: 0.25rem; }

@media print {
  :global(aside), :global(nav.sidebar), :global(header.topbar), :global(.no-print) { display: none !important; }
  :global(body), :global(html) { background: white !important; }
  :global(main), :global(.max-w-5xl) { max-width: none !important; margin: 0 !important; padding: 0 !important; }
  .manual { border: none !important; box-shadow: none !important; padding: 0 !important; }
  .section-block { break-inside: avoid; page-break-inside: avoid; }
  .print-toc { break-after: page; page-break-after: always; }
  a { color: black !important; text-decoration: none !important; }
}
</style>
