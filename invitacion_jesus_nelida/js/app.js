// Initialize AOS (Animate on Scroll)
AOS.init({
  duration: 1200,
  once: true,
  easing: 'ease-in-out'
});

// Elements
const seal = document.getElementById('seal');
const envelope = document.getElementById('envelope');
const envelopeContainer = document.getElementById('envelope-container');
const weddingPage = document.getElementById('wedding-page');
const bgMusic = document.getElementById('bg-music');
const musicControl = document.getElementById('music-control');

// Music Playback Logic
let isPlaying = false;

function playMusic() {
  bgMusic.play()
    .then(() => {
      isPlaying = true;
      musicControl.classList.add('playing');
    })
    .catch((error) => {
      console.log('Reproducción automática prevenida:', error);
    });
}

function toggleMusic() {
  if (isPlaying) {
    bgMusic.pause();
    isPlaying = false;
    musicControl.classList.remove('playing');
  } else {
    playMusic();
  }
}

// Attach event listener for floating music control
musicControl.addEventListener('click', toggleMusic);

// Envelope Opening Animation Transition
seal.addEventListener('click', () => {
  // Add CSS open class to start 3D flip & card translation
  envelope.classList.add('open');
  
  // Try to start music after user interaction (seal click)
  playMusic();
  
  // Wait for envelope open animation to complete (1.5 seconds)
  setTimeout(() => {
    // Fade out and scale up the envelope screen
    gsap.to(envelopeContainer, {
      opacity: 0,
      scale: 1.2,
      duration: 1.2,
      ease: 'power2.inOut',
      onComplete: () => {
        envelopeContainer.style.display = 'none';
      }
    });
    
    // Reveal and fade in the wedding invitation content
    weddingPage.style.display = 'block';
    gsap.to(weddingPage, {
      opacity: 1,
      duration: 1.2,
      ease: 'power2.out',
      onStart: () => {
        // Refresh AOS to calculate offsets now that page is visible
        setTimeout(() => {
          AOS.refresh();
        }, 150);
        // Dispatch resize event to force iframe and calculations update
        window.dispatchEvent(new Event('resize'));
      }
    });
  }, 1600);
});

// Countdown Timer Logic
const targetDate = new Date("October 2, 2026 20:00:00").getTime();

function updateCountdown() {
  const now = new Date().getTime();
  const timeDifference = targetDate - now;

  // Select DOM nodes
  const dNode = document.getElementById('d');
  const hNode = document.getElementById('h');
  const mNode = document.getElementById('m');
  const sNode = document.getElementById('s');

  if (!dNode || !hNode || !mNode || !sNode) return;

  if (timeDifference <= 0) {
    dNode.innerHTML = '00';
    hNode.innerHTML = '00';
    mNode.innerHTML = '00';
    sNode.innerHTML = '00';
    return;
  }

  const days = Math.floor(timeDifference / (1000 * 60 * 60 * 24));
  const hours = Math.floor((timeDifference % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60));
  const minutes = Math.floor((timeDifference % (1000 * 60 * 60)) / (1000 * 60));
  const seconds = Math.floor((timeDifference % (1000 * 60)) / 1000);

  // Format with leading zero if single digit
  dNode.innerHTML = days < 10 ? '0' + days : days;
  hNode.innerHTML = hours < 10 ? '0' + hours : hours;
  mNode.innerHTML = minutes < 10 ? '0' + minutes : minutes;
  sNode.innerHTML = seconds < 10 ? '0' + seconds : seconds;
}

// Initial calculation to prevent showing 00 on load
updateCountdown();

// Update every second
setInterval(updateCountdown, 1000);

// ============================================
// FUNCIÓN: GUARDAR RECORDATORIO EN EL CALENDARIO
// ============================================
function downloadICS() {
  const startDateUTC = "20261003T000000Z";
  const endDateUTC = "20261003T080000Z";
  
  const icsContent = `BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Boda Jesús y Nélida//ES
CALSCALE:GREGORIAN
METHOD:PUBLISH
BEGIN:VEVENT
UID:${Date.now()}@bodajesusynelida
DTSTAMP:${new Date().toISOString().replace(/[-:]/g, '').split('.')[0]}Z
DTSTART:${startDateUTC}
DTEND:${endDateUTC}
SUMMARY:Boda de Jesús y Nélida
DESCRIPTION:¡Celebramos nuestra unión! Te esperamos en Trinidad, Beni - Bolivia.\\n\\nCeremonia: 20:00 hrs\\nRecepción: 21:00 hrs\\nCena: 22:30 hrs\\nFiesta: 23:30 hrs\\n\\nCódigo de vestimenta: Formal / Gala.
LOCATION:Domicilio de la familia Fuentes, Trinidad, Beni - Bolivia
CATEGORIES:CELEBRATION
STATUS:CONFIRMED
SEQUENCE:0
BEGIN:VALARM
TRIGGER:-PT48H
ACTION:DISPLAY
DESCRIPTION:Recordatorio: La boda de Jesús y Nélida es en 2 días
END:VALARM
END:VEVENT
END:VCALENDAR`;

  const blob = new Blob([icsContent], { type: "text/calendar;charset=utf-8" });
  const link = document.createElement("a");
  link.href = URL.createObjectURL(blob);
  link.download = "recordatorio_boda_Jesus_Nelida.ics";
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(link.href);
  
  alert("✅ Recordatorio guardado. Revisa tu calendario.");
}

// Asignar el evento al botón de recordatorio (espera a que el DOM cargue)
document.addEventListener('DOMContentLoaded', function() {
  const reminderBtn = document.getElementById('saveReminderBtn');
  if (reminderBtn) {
    reminderBtn.addEventListener('click', downloadICS);
  }
});