//= require action_cable
//= require_self

(function() {
  this.LlamaBotRails = this.LlamaBotRails || {};
  LlamaBotRails.cable = ActionCable.createConsumer();
}).call(this); 