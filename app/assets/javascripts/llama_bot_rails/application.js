//= require action_cable
//= require_self

(function () {
  this.LlamaBotRails = this.LlamaBotRails || {};

  function createLlamaCable() {
    if (window.ActionCable && !LlamaBotRails.cable) {
      console.log("🦙 Creating LlamaBot ActionCable consumer");
      LlamaBotRails.cable = ActionCable.createConsumer();
    }
  }

  // Run immediately if ActionCable is already present (classic asset pipeline)
  if (window.ActionCable) {
    createLlamaCable();
  } else {
    // Wait until DOM + importmap load finishes
    document.addEventListener("DOMContentLoaded", createLlamaCable);
    document.addEventListener("turbo:load", createLlamaCable); // covers Turbo + importmap apps
  }
}).call(this);