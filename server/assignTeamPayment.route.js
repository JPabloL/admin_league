/**
 * Flutter → POST /assignTeamPayment y POST /assignTeamPaymentsBulk (mismo baseUrl que el resto).
 *
 * Opción A — Todo en tu archivo de rutas (como saveAction):
 *   Copia las funciones buildPaymentRegistration … sendTeamPaymentPush y el cuerpo de
 *   registerAssignTeamPaymentRoutes (los dos router.post) donde ya tienes `router` y `admas`.
 *
 * Opción B — Una línea en tu servidor:
 *   const registerAssignTeamPaymentRoutes = require('./assignTeamPayment.route');
 *   registerAssignTeamPaymentRoutes(router, admas);
 *
 * Requiere: app.set('pushService', fn) y app.set('socketio', io)
 */

function buildPaymentRegistration({
  mood,
  amount,
  currency,
  actingUserId,
  assignedByUserName,
  notes,
}) {
  return {
    at: new Date().toISOString(),
    amount: amount != null && amount !== '' ? Number(amount) : null,
    currency: currency || 'MXN',
    assignedByUserId: actingUserId || null,
    assignedByUserName: assignedByUserName || '',
    notes: notes || '',
    mood,
  };
}

async function insertTeamPaymentAuditDoc(admas, payload) {
  const {
    teamDoc,
    previousMood,
    mood,
    amount,
    currency,
    actingUserId,
    assignedByUserName,
    notes,
  } = payload;
  const tournamentId =
    teamDoc.tournament?._id ||
    teamDoc.tournament?.id ||
    teamDoc.tournamentId ||
    null;
  const action =
    previousMood === 0 && Number(mood) !== 0
      ? 'payment_added'
      : previousMood !== 0 && Number(mood) === 0
        ? 'payment_removed'
        : 'payment_updated';

  const actionText =
    action === 'payment_added'
      ? 'Pago agregado'
      : action === 'payment_removed'
        ? 'Pago quitado'
        : 'Pago actualizado';

  const audit = {
    type: 'team_payment',
    teamId: teamDoc._id,
    teamName: teamDoc.name || '',
    tournamentId,
    previousMood: previousMood ?? 0,
    mood,
    action,
    actionText,
    amount: amount != null && amount !== '' ? Number(amount) : null,
    currency: currency || 'MXN',
    assignedByUserId: actingUserId || null,
    assignedByUserName: assignedByUserName || '',
    notes: notes || '',
    createdAt: new Date().toISOString(),
  };
  return admas.insert(audit);
}

function emitTeamPaymentSocket(io, teamDoc, payload) {
  if (!io) return;
  const tournamentId =
    teamDoc.tournament?._id ||
    teamDoc.tournament?.id ||
    teamDoc.tournamentId;
  if (tournamentId) {
    io.to(String(tournamentId)).emit('team_payment_updated', payload);
  }
  const academyId = teamDoc.academy?.id || teamDoc.academy?._id;
  if (academyId) {
    io.to(String(academyId)).emit('team_payment_updated', payload);
  }
}

async function sendTeamPaymentPush(admas, sendPush, teamDoc, mood, assignedByUserName) {
  if (!sendPush) return;
  try {
    const academyId = teamDoc.academy?.id || teamDoc.academy?._id;
    if (!academyId) return;
    const academyDoc = await admas.get(academyId).catch(() => null);
    if (!academyDoc || !academyDoc.fcm_token) return;
    const teamName = teamDoc.name || 'Equipo';
    const titulo =
      mood === 0
        ? `Inscripción sin pago: ${teamName}`
        : `Pago registrado: ${teamName}`;
    const mensaje =
      mood === 0
        ? `Se marcó como sin pago.${assignedByUserName ? ` Por ${assignedByUserName}.` : ''}`
        : `Inscripción con pago registrada.${assignedByUserName ? ` Por ${assignedByUserName}.` : ''}`;
    sendPush(academyDoc.fcm_token, titulo, mensaje, {
      tipo: 'team_payment_update',
      teamId: teamDoc._id,
      mood: String(mood),
    });
  } catch (e) {
    console.log('==> [ERR PUSH team_payment] No crítico:', e.message);
  }
}

function registerAssignTeamPaymentRoutes(router, admas) {
  router.post('/assignTeamPayment', async (req, res) => {
  console.log('==> [LOG] Petición recibida en assignTeamPayment');

  const params = req.body;
  const sendPush = req.app.get('pushService');
  const io = req.app.get('socketio');
  const tokenValido = '3es_ldo5%4d';

  const actingUserId = params.actingUserId;
  const assignedByUserName = params.assignedByUserName;
  const teamId = params.teamId || params._id || params.id;
  const mood = params.mood;
  const amount = params.amount;
  const currency = params.currency;
  const notes = params.notes;

  if (params.token !== tokenValido) {
    return res.status(401).json({ status: 'error', message: 'Error de sesión' });
  }

  if (!teamId) {
    return res.status(400).json({ status: 'error', message: 'teamId requerido' });
  }

  try {
    let teamDoc = await admas.get(teamId);
    const previousMood = teamDoc.mood != null ? Number(teamDoc.mood) : 0;
    const nextMood = Number(mood);

    teamDoc.mood = nextMood;
    teamDoc.paymentRegistration = buildPaymentRegistration({
      mood: nextMood,
      amount,
      currency,
      actingUserId,
      assignedByUserName,
      notes,
    });
    teamDoc.updatedAt = new Date().toISOString();
    if (actingUserId) teamDoc.updatedBy = actingUserId;

    const saveRes = await admas.insert(teamDoc);

    try {
      await insertTeamPaymentAuditDoc(admas, {
        teamDoc,
        previousMood,
        mood: nextMood,
        amount,
        currency,
        actingUserId,
        assignedByUserName,
        notes,
      });
    } catch (auditErr) {
      console.log('==> [WARN] Auditoría team_payment:', auditErr.message);
    }

    const socketPayload = {
      team: {
        _id: saveRes.id || teamDoc._id,
        _rev: saveRes.rev,
        mood: nextMood,
        paymentRegistration: teamDoc.paymentRegistration,
      },
    };
    emitTeamPaymentSocket(io, teamDoc, socketPayload);
    await sendTeamPaymentPush(admas, sendPush, teamDoc, nextMood, assignedByUserName);

    return res.json({
      status: 'ok',
      team: {
        _id: saveRes.id || teamDoc._id,
        _rev: saveRes.rev,
        mood: nextMood,
        paymentRegistration: teamDoc.paymentRegistration,
      },
    });
  } catch (err) {
    console.error('==> [ERR] assignTeamPayment:', err);
    return res.status(500).json({ status: 'error', message: err.message });
  }
});

router.post('/assignTeamPaymentsBulk', async (req, res) => {
  console.log('==> [LOG] Petición recibida en assignTeamPaymentsBulk');

  const params = req.body;
  const sendPush = req.app.get('pushService');
  const io = req.app.get('socketio');
  const tokenValido = '3es_ldo5%4d';

  const actingUserId = params.actingUserId;
  const assignedByUserName = params.assignedByUserName;
  const defaultAmount = params.amount;
  const currency = params.currency;
  const notes = params.notes;
  const updates = params.updates || params.items;

  if (params.token !== tokenValido) {
    return res.status(401).json({ status: 'error', message: 'Error de sesión' });
  }

  if (!Array.isArray(updates) || updates.length === 0) {
    return res.status(400).json({ status: 'error', message: 'updates[] requerido' });
  }

  const results = [];

  try {
    for (const u of updates) {
      const tid = u.teamId || u._id || u.id;
      const m = u.mood;
      const amountOne = u.amount != null ? u.amount : defaultAmount;

      let teamDoc = await admas.get(tid);
      const previousMood = teamDoc.mood != null ? Number(teamDoc.mood) : 0;
      const nextMood = Number(m);

      teamDoc.mood = nextMood;
      teamDoc.paymentRegistration = buildPaymentRegistration({
        mood: nextMood,
        amount: amountOne,
        currency,
        actingUserId,
        assignedByUserName,
        notes: u.notes != null ? u.notes : notes,
      });
      teamDoc.updatedAt = new Date().toISOString();
      if (actingUserId) teamDoc.updatedBy = actingUserId;

      const saveRes = await admas.insert(teamDoc);

      try {
        await insertTeamPaymentAuditDoc(admas, {
          teamDoc,
          previousMood,
          mood: nextMood,
          amount: amountOne,
          currency,
          actingUserId,
          assignedByUserName,
          notes: u.notes != null ? u.notes : notes,
        });
      } catch (auditErr) {
        console.log('==> [WARN] Auditoría team_payment:', auditErr.message);
      }

      results.push({
        _id: saveRes.id || teamDoc._id,
        _rev: saveRes.rev,
        mood: nextMood,
        paymentRegistration: teamDoc.paymentRegistration,
      });
    }

    const tournamentId =
      params.tournamentIdForSocket || params.tournamentId;
    if (io && tournamentId) {
      io.to(String(tournamentId)).emit('team_payments_bulk', {
        count: results.length,
        teams: results,
        actingUserId,
      });
    } else if (io && results.length) {
      io.emit('team_payments_bulk', {
        count: results.length,
        teams: results,
        actingUserId,
      });
    }

    return res.json({ status: 'ok', teams: results });
  } catch (err) {
    console.error('==> [ERR] assignTeamPaymentsBulk:', err);
    return res.status(500).json({ status: 'error', message: err.message });
  }
  });
}

module.exports = registerAssignTeamPaymentRoutes;
