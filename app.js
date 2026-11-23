import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const groups = {
  friends: {
    label: "Amigos",
    emailDomain: "amigo-invisible.test",
    drawFunction: "get_my_draw",
    wishlistTable: "wishlist_items",
    participants: [
      ["marc", "Marc"],
      ["ernest", "Ernest"],
      ["carla", "Carla"],
      ["noe", "Noe"],
      ["jonay", "Jonay"],
      ["oriol", "Oriol"],
      ["ivan", "Ivan"],
      ["nikola", "Nikola"],
      ["aoxin", "Aoxin"],
      ["cai", "Cai"],
    ],
    rules: [
      "El regalo no debe superar los 15 €.",
      "No se pueden regalar Funkos.",
      "No se pueden regalar 30 grapadoras (una roja).",
      "Mantenemos en secreto a quién nos ha tocado.",
      "La lista de deseos sirve de inspiración.",
    ],
  },
  family: {
    label: "Familia",
    emailDomain: "amigo-invisible.test",
    drawFunction: "get_my_family_draw",
    wishlistTable: "family_wishlist_items",
    participants: [
      ["marc", "Marc"],
      ["andrea", "Andrea"],
      ["elena", "Elena"],
      ["iona", "Iona"],
      ["eva", "Eva"],
      ["ana", "Ana"],
    ],
    rules: [
      "El regalo no puede superar los 20 €.",
      "La lista de deseos sirve de inspiración.",
      "Mantener en secreto lo que nos ha tocado.",
    ],
  },
};

const config = window.APP_CONFIG;
const loginView = document.querySelector("#login-view");
const appView = document.querySelector("#app-view");
const loginForm = document.querySelector("#login-form");
const loginMessage = document.querySelector("#login-message");
const wishlistForm = document.querySelector("#wishlist-form");
const ownListMessage = document.querySelector("#own-list-message");
const recipientListMessage = document.querySelector("#recipient-list-message");
const ownWishlist = document.querySelector("#own-wishlist");
const recipientWishlist = document.querySelector("#recipient-wishlist");
const participantSelect = document.querySelector("#participant");
const groupSwitch = document.querySelector("#group-switch");
const groupMessage = document.querySelector("#group-message");

let supabase;
let profile;
let currentGroup = localStorage.getItem("draw-group") === "family" ? "family" : "friends";

function renderGroup(groupName) {
  currentGroup = groupName;
  localStorage.setItem("draw-group", currentGroup);
  const group = groups[currentGroup];
  const placeholder = document.createElement("option");
  placeholder.value = "";
  placeholder.textContent = "Selecciona tu nombre";
  placeholder.disabled = true;
  placeholder.selected = true;
  participantSelect.replaceChildren(placeholder);

  for (const [username, name] of group.participants) {
    const option = document.createElement("option");
    option.value = username;
    option.textContent = name;
    participantSelect.append(option);
  }

  groupSwitch.querySelectorAll("[data-group]").forEach((button) => {
    const isActive = button.dataset.group === currentGroup;
    button.classList.toggle("is-active", isActive);
    button.setAttribute("aria-pressed", String(isActive));
  });
  document.querySelector("#edition").textContent = `SORTEO DE ${group.label.toUpperCase()}`;
  document.querySelector("#welcome-eyebrow").lastChild.textContent =
    ` UN SECRETO ENTRE ${group.label.toUpperCase()}`;

  for (const listId of ["#public-rules-list", "#app-rules-list"]) {
    const list = document.querySelector(listId);
    list.replaceChildren(...group.rules.map((rule) => {
      const item = document.createElement("li");
      item.textContent = rule;
      return item;
    }));
  }
}

function setMessage(element, text, isError = false) {
  element.textContent = text;
  element.classList.toggle("message-error", isError);
}

function showLogin() {
  profile = undefined;
  appView.classList.add("hidden");
  loginView.classList.remove("hidden");
}

function showApp() {
  loginView.classList.add("hidden");
  appView.classList.remove("hidden");
}

async function switchGroup(groupName) {
  if (groupName === currentGroup) return;

  const { data, error: sessionError } = await supabase?.auth.getSession() ?? {
    data: { session: null },
    error: null,
  };
  if (sessionError) {
    setMessage(groupMessage, "No se pudo comprobar la sesión. Inténtalo de nuevo.", true);
    console.error("Error al comprobar la sesión:", sessionError.message);
    return;
  }

  if (data.session) {
    const { error } = await supabase.auth.signOut();
    if (error) {
      setMessage(groupMessage, "No se pudo cambiar de sorteo. Inténtalo de nuevo.", true);
      console.error("Error al cambiar de sorteo:", error.message);
      return;
    }
    showLogin();
  }

  loginForm.reset();
  setMessage(loginMessage, "");
  setMessage(groupMessage, "");
  renderGroup(groupName);
}

function renderWishlist(list, items, canDelete, messageElement) {
  list.replaceChildren();

  if (items.length === 0) {
    const empty = document.createElement("li");
    empty.className = "empty-list";
    empty.textContent = canDelete
      ? "Todavía no has añadido ninguna idea."
      : "Todavía no ha compartido ninguna idea.";
    list.append(empty);
    return;
  }

  for (const item of items) {
    const row = document.createElement("li");
    row.className = "wishlist-item";
    const text = document.createElement("span");
    text.textContent = item.content;
    row.append(text);

    if (canDelete) {
      const remove = document.createElement("button");
      remove.className = "remove-button";
      remove.type = "button";
      remove.textContent = "Quitar";
      remove.setAttribute("aria-label", `Quitar: ${item.content}`);
      remove.addEventListener("click", () => deleteWish(item.id, messageElement));
      row.append(remove);
    }

    list.append(row);
  }
}

async function loadWishlist(ownerId, list, canDelete, messageElement) {
  const { wishlistTable } = groups[currentGroup];
  const { data, error } = await supabase
    .from(wishlistTable)
    .select("id, content, created_at")
    .eq("owner_id", ownerId)
    .order("created_at", { ascending: true });

  if (error) {
    setMessage(messageElement, "No se pudo cargar la lista. Inténtalo de nuevo.", true);
    console.error("Error al cargar la lista de deseos:", error.message);
    return;
  }

  setMessage(messageElement, "");
  renderWishlist(list, data, canDelete, messageElement);
}

async function loadProfile() {
  const { drawFunction } = groups[currentGroup];
  const { data, error } = await supabase.rpc(drawFunction);
  if (error) {
    setMessage(loginMessage, "No se pudo cargar tu sorteo. Contacta con quien organiza el grupo.", true);
    console.error("Error al cargar el sorteo:", error.message);
    await supabase.auth.signOut();
    return;
  }

  profile = data?.[0];
  if (!profile) {
    setMessage(loginMessage, "No encontramos tu participante. Contacta con quien organiza el grupo.", true);
    await supabase.auth.signOut();
    return;
  }

  document.querySelector("#my-name").textContent = profile.my_name;
  document.querySelector("#recipient-name").textContent = profile.recipient_name ?? "Sorteo pendiente";
  document.querySelector("#recipient-list-name").textContent = profile.recipient_name ?? "tu persona secreta";
  showApp();

  if (!profile.recipient_id) {
    setMessage(recipientListMessage, "El sorteo todavía no está configurado.");
    recipientWishlist.replaceChildren();
  } else {
    await loadWishlist(profile.recipient_id, recipientWishlist, false, recipientListMessage);
  }
  await loadWishlist(profile.my_id, ownWishlist, true, ownListMessage);
}

async function deleteWish(id, messageElement) {
  const { wishlistTable } = groups[currentGroup];
  const { error } = await supabase.from(wishlistTable).delete().eq("id", id);
  if (error) {
    setMessage(messageElement, "No se pudo quitar la idea. Inténtalo de nuevo.", true);
    console.error("Error al quitar una idea:", error.message);
    return;
  }
  await loadWishlist(profile.my_id, ownWishlist, true, ownListMessage);
}

function isConfigured() {
  return (
    config &&
    config.supabaseUrl.startsWith("https://") &&
    !config.supabaseUrl.includes("PEGA_AQUI") &&
    config.supabaseAnonKey &&
    !config.supabaseAnonKey.includes("PEGA_AQUI")
  );
}

renderGroup(currentGroup);

groupSwitch.addEventListener("click", async (event) => {
  const button = event.target.closest("[data-group]");
  if (button) await switchGroup(button.dataset.group);
});

if (!isConfigured()) {
  loginForm.querySelector("button[type='submit']").disabled = true;
  setMessage(loginMessage, "Falta conectar Supabase. Sigue los pasos de configuración del proyecto.", true);
} else {
  supabase = createClient(config.supabaseUrl, config.supabaseAnonKey);

  loginForm.addEventListener("submit", async (event) => {
    event.preventDefault();
    const button = loginForm.querySelector("button[type='submit']");
    button.disabled = true;
    setMessage(loginMessage, "Comprobando…");

    const username = new FormData(loginForm).get("participant");
    const password = new FormData(loginForm).get("password");
    const { emailDomain } = groups[currentGroup];
    const { error } = await supabase.auth.signInWithPassword({
      email: `${username}@${emailDomain}`,
      password,
    });

    if (error) {
      setMessage(loginMessage, "Nombre o contraseña incorrectos.", true);
      button.disabled = false;
      return;
    }

    loginForm.reset();
    setMessage(loginMessage, "");
    await loadProfile();
    button.disabled = false;
  });

  wishlistForm.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (!profile) return;

    const input = wishlistForm.elements.wish;
    const content = input.value.trim();
    if (!content) return;

    const button = wishlistForm.querySelector("button[type='submit']");
    button.disabled = true;
    const { wishlistTable } = groups[currentGroup];
    const { error } = await supabase
      .from(wishlistTable)
      .insert({ owner_id: profile.my_id, content });

    if (error) {
      setMessage(ownListMessage, "No se pudo guardar la idea. Inténtalo de nuevo.", true);
      console.error("Error al guardar una idea:", error.message);
    } else {
      input.value = "";
      await loadWishlist(profile.my_id, ownWishlist, true, ownListMessage);
    }
    button.disabled = false;
  });

  document.querySelector("#logout-button").addEventListener("click", async () => {
    const { error } = await supabase.auth.signOut();
    if (error) {
      setMessage(recipientListMessage, "No se pudo cerrar la sesión. Inténtalo de nuevo.", true);
      console.error("Error al cerrar sesión:", error.message);
      return;
    }
    showLogin();
  });

  supabase.auth.getSession().then(({ data, error }) => {
    if (error) {
      setMessage(loginMessage, "No se pudo recuperar la sesión. Vuelve a entrar.", true);
      console.error("Error al recuperar la sesión:", error.message);
      return;
    }
    if (data.session) loadProfile();
  });
}
