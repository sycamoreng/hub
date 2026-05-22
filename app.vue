<script setup lang="ts">
const splashVisible = ref(true)
onMounted(() => {
  setTimeout(() => { splashVisible.value = false }, 800)
})
</script>

<template>
  <Transition name="splash-fade">
    <div v-if="splashVisible" class="splash-screen">
      <img src="/logo-icon.png" alt="Sycamore" class="splash-logo" />
      <div class="splash-name">Sycamore</div>
    </div>
  </Transition>
  <NuxtLayout>
    <NuxtPage />
  </NuxtLayout>
  <ToastStack />
</template>

<style>
.splash-screen {
  position: fixed;
  inset: 0;
  z-index: 9999;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  background: linear-gradient(135deg, #1f6f9c 0%, #0a445c 100%);
}
.splash-logo {
  width: 72px;
  height: 72px;
  border-radius: 16px;
  animation: splash-pop 0.4s ease-out;
}
.splash-name {
  margin-top: 16px;
  color: #fff;
  font-family: 'Satoshi', system-ui, sans-serif;
  font-size: 20px;
  font-weight: 700;
  letter-spacing: -0.01em;
  opacity: 0.9;
}
.splash-fade-leave-active {
  transition: opacity 0.3s ease;
}
.splash-fade-leave-to {
  opacity: 0;
}
@keyframes splash-pop {
  0% { transform: scale(0.7); opacity: 0; }
  100% { transform: scale(1); opacity: 1; }
}
</style>
