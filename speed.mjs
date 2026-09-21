// Explicit standard speed clears any tier inherited from an older conversation.
export function turnSpeed(value, modelId, models) {
  const tier=value || 'default';
  if(tier==='default')return {serviceTierForTurn:'default'};
  const model=models.find(m=>m.model===modelId)||(!modelId?models.find(m=>m.isDefault):null);
  if(tier!=='priority' || !model?.serviceTiers?.some(t=>t.id===tier))throw new Error('当前模型不支持加速，请选择标准速度');
  return {serviceTierForTurn:tier};
}
