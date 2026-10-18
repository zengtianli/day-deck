#!/usr/bin/env python3
"""本轮单 App 接续记录；仅通过原 asc SDK 操作 TestFlight。"""
import datetime as dt
import hashlib
import json
import pathlib
import subprocess
import sys

sys.path.insert(0, '/Users/tianli/Dev/tools/dev/lib/tools/macapp/ios')
import asc

ROOT = pathlib.Path(__file__).resolve().parent
APP = '6807048407'
BUILD = '72f350f5-d7c4-4427-9283-34ac9054a0b0'
VERSION = '9cef653d-f6ed-4163-b70e-ec08130c8599'
EMAILS = [f'zengtianli{i}@126.com' for i in (1, 2, 3)]
GROUP_NAME = 'Notihub iOS External Beta'
CLAIM = ['/Users/tianli/Dev/.venv/bin/python',
         '/Users/tianli/Dev/tools/cc-home/tools/harness/claims.py',
         '--pid', '35999', '--session', 'chapter-task:755ffd6eb22d4f908508c471cff5f506', 'check']
RECEIPTS = ROOT / 'receipts.json'
events = json.loads(RECEIPTS.read_text()) if RECEIPTS.exists() else []


def safe(value):
    if isinstance(value, dict):
        out = {}
        for key, val in value.items():
            if key in ('demoAccountName', 'demoAccountPassword', 'notes', 'contactPhone') and isinstance(val, str) and val:
                out[key] = {'redacted': True, 'length': len(val),
                            'sha256': hashlib.sha256(val.encode()).hexdigest()}
            else:
                out[key] = safe(val)
        return out
    if isinstance(value, list):
        return [safe(x) for x in value]
    return value


def save(name, data):
    path = ROOT / name
    subprocess.run(CLAIM + [str(path)], check=True, capture_output=True)
    path.write_text(json.dumps(safe(data), ensure_ascii=False, indent=2) + '\n')


def record(kind, **data):
    events.append({'at': dt.datetime.now(dt.timezone.utc).isoformat(), 'kind': kind, **data})
    save('receipts.json', events)


def get(path, params=None):
    result = asc.get(path, params)
    record('api_read', path=path, params=params, response=result)
    return result


def all_data(path, params=None):
    result = get(path, params)
    rows = result['data']
    included = result.get('included', [])
    while result.get('links', {}).get('next'):
        result = get(result['links']['next'].split('/v1', 1)[1])
        rows += result['data']
        included += result.get('included', [])
    return rows, included


def write(method, path, body):
    # 明确排除正式 App Store 的所有写接口。
    assert path.split('/')[1] in {
        'betaGroups', 'betaTesters', 'betaAppReviewDetails', 'betaAppLocalizations',
        'betaBuildLocalizations', 'buildBetaDetails', 'betaAppReviewSubmissions'}
    record('write_intent', method=method, path=path, request=body)
    try:
        result = getattr(asc, method.lower())(path, body)
    except BaseException as exc:
        record('write_error', method=method, path=path, error=str(exc))
        raise
    record('write_receipt', method=method, path=path, response=result)
    print(method, path, 'OK', flush=True)
    return result


def formal():
    versions, _ = all_data(f'/apps/{APP}/appStoreVersions', {'limit': 200})
    submissions, _ = all_data('/reviewSubmissions', {'filter[app]': APP, 'limit': 200})
    builds = {v['id']: get(f"/appStoreVersions/{v['id']}/relationships/build")['data']
              for v in versions}
    detail = get(f'/appStoreVersions/{VERSION}/appStoreReviewDetail')['data']
    locs, _ = all_data(f'/appStoreVersions/{VERSION}/appStoreVersionLocalizations', {'limit': 200})
    return {'versions': versions, 'submissions': submissions, 'builds': builds,
            'review_detail': detail, 'localizations': locs}


def main():
    app = get(f'/apps/{APP}')['data']
    assert app['attributes']['bundleId'] == 'cyou.tianli.daydeck'
    builds, releases = all_data('/builds', {
        'filter[app]': APP, 'filter[preReleaseVersion.platform]': 'IOS',
        'include': 'preReleaseVersion', 'limit': 200})
    valid = [b for b in builds if b['attributes']['processingState'] == 'VALID'
             and b['attributes']['expired'] is False
             and dt.datetime.fromisoformat(b['attributes']['expirationDate']) > dt.datetime.now(dt.timezone.utc)]
    selected = asc.newest_valid([{'id': b['id'], **b['attributes']} for b in valid])
    latest = next((b for b in valid if selected and b['id'] == selected['id']), None)
    assert latest and latest['id'] == BUILD, '最新有效包变化，重新审阅对象'
    release_id = latest['relationships']['preReleaseVersion']['data']['id']
    release = next(r for r in releases if r['id'] == release_id)
    assert release['attributes'] == {'version': '0.2.2', 'platform': 'IOS'}
    before = formal()
    save('formal-before.json', before) if not (ROOT / 'formal-before.json').exists() else None
    groups, _ = all_data(f'/apps/{APP}/betaGroups', {'limit': 200})
    beta_review = get(f'/apps/{APP}/betaAppReviewDetail')['data']
    localizations, _ = all_data(f'/apps/{APP}/betaAppLocalizations', {'limit': 200})
    beta_build_locs, _ = all_data(f'/builds/{BUILD}/betaBuildLocalizations', {'limit': 200})
    beta_detail = get(f'/builds/{BUILD}/buildBetaDetail')['data']
    submissions, _ = all_data('/betaAppReviewSubmissions', {'filter[build]': BUILD, 'limit': 200})
    save('plan.json', {'source_head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
                      'app': app, 'build': latest, 'release': release, 'groups': groups,
                      'beta_review': beta_review, 'beta_app_localizations': localizations,
                      'beta_build_localizations': beta_build_locs, 'beta_detail': beta_detail,
                      'beta_submissions': submissions}) if not (ROOT / 'plan.json').exists() else None
    if sys.argv[1:] == ['baseline']:
        print(json.dumps({'build': BUILD, 'number': latest['attributes']['version'],
                          'release': release['attributes'], 'groups': len(groups),
                          'beta_submissions': len(submissions)}, ensure_ascii=False))
        return
    assert sys.argv[1:] == ['configure']
    review_attrs = before['review_detail']['attributes']
    fields = ('contactFirstName', 'contactLastName', 'contactPhone', 'contactEmail',
              'demoAccountRequired', 'demoAccountName', 'demoAccountPassword', 'notes')
    assert all(review_attrs.get(k) for k in fields[:4]), '正式审核联系人不完整'
    if review_attrs.get('demoAccountRequired'):
        assert review_attrs.get('demoAccountName') and review_attrs.get('demoAccountPassword')
    review_copy = {k: review_attrs.get(k) for k in fields}
    if any(beta_review['attributes'].get(k) != v for k, v in review_copy.items()):
        write('PATCH', f"/betaAppReviewDetails/{beta_review['id']}", {
            'data': {'type': 'betaAppReviewDetails', 'id': beta_review['id'], 'attributes': review_copy}})
    copied = get(f'/apps/{APP}/betaAppReviewDetail')['data']
    assert all(copied['attributes'].get(k) == v for k, v in review_copy.items())
    record('review_copy_verified', fields=list(fields), exact_match=True)

    store_loc = next(x for x in before['localizations'] if x['attributes']['locale'] == 'zh-Hans')
    infos, _ = all_data(f'/apps/{APP}/appInfos', {'limit': 200})
    info_locs = []
    for info in infos:
        rows, _ = all_data(f"/appInfos/{info['id']}/appInfoLocalizations", {'limit': 200})
        info_locs += rows
    privacy = next(x['attributes']['privacyPolicyUrl'] for x in info_locs
                   if x['attributes']['locale'] == 'zh-Hans' and x['attributes'].get('privacyPolicyUrl'))
    attrs = {'locale': 'zh-Hans', 'description': store_loc['attributes']['description'],
             'feedbackEmail': review_attrs['contactEmail'], 'privacyPolicyUrl': privacy}
    loc = next((x for x in localizations if x['attributes']['locale'] == 'zh-Hans'), None)
    if loc is None:
        write('POST', '/betaAppLocalizations', {'data': {'type': 'betaAppLocalizations', 'attributes': attrs,
              'relationships': {'app': {'data': {'type': 'apps', 'id': APP}}}}})
    elif any(loc['attributes'].get(k) != v for k, v in attrs.items()):
        write('PATCH', f"/betaAppLocalizations/{loc['id']}", {
            'data': {'type': 'betaAppLocalizations', 'id': loc['id'], 'attributes': attrs}})

    whats_new = ('请在 iPhone/iPad 测试主要流程：\n'
                 '1. 在「连接」使用已有服务访问资格连接；也可按审核说明使用隔离的合成数据账号。\n'
                 '2. 在「今天」搜索和查看待办、展开详情、更新完成/不做了状态；主动加入本机提醒事项并检查重复提示。\n'
                 '3. 在「通知」切换已有日期、搜索摘要与时间线，展开长正文。\n'
                 '4. 在「随手记」保存文字并刷新回读；断网后检查草稿保留、缓存时间与重连恢复。\n'
                 '5. 检查 iPad 宽窄布局、设置导入导出及默认关闭的 iCloud 配置同步；有配对 Apple Watch 时查看摘要。\n'
                 '请反馈无法完成的操作、错误信息、内容显示异常及难理解或不顺手之处，并注明设备、系统版本和复现步骤。')
    loc = next((x for x in beta_build_locs if x['attributes']['locale'] == 'zh-Hans'), None)
    if loc is None:
        write('POST', '/betaBuildLocalizations', {'data': {'type': 'betaBuildLocalizations',
              'attributes': {'locale': 'zh-Hans', 'whatsNew': whats_new},
              'relationships': {'build': {'data': {'type': 'builds', 'id': BUILD}}}}})
    elif loc['attributes'].get('whatsNew') != whats_new:
        write('PATCH', f"/betaBuildLocalizations/{loc['id']}", {'data': {
            'type': 'betaBuildLocalizations', 'id': loc['id'], 'attributes': {'whatsNew': whats_new}}})
    if beta_detail['attributes']['autoNotifyEnabled'] is not True:
        write('PATCH', f"/buildBetaDetails/{beta_detail['id']}", {'data': {
            'type': 'buildBetaDetails', 'id': beta_detail['id'], 'attributes': {'autoNotifyEnabled': True}}})

    group = next((g for g in groups if g['attributes']['name'] == GROUP_NAME
                  and g['attributes']['isInternalGroup'] is False), None)
    if group is None:
        group = write('POST', '/betaGroups', {'data': {'type': 'betaGroups',
            'attributes': {'name': GROUP_NAME, 'isInternalGroup': False, 'publicLinkEnabled': False},
            'relationships': {'app': {'data': {'type': 'apps', 'id': APP}}}}})['data']
    gid = group['id']
    for email in EMAILS:
        members, _ = all_data(f'/betaGroups/{gid}/betaTesters', {'limit': 200})
        if any(x['attributes'].get('email', '').lower() == email for x in members):
            continue
        testers, _ = all_data('/betaTesters', {'filter[apps]': APP, 'filter[email]': email, 'limit': 200})
        assert len(testers) <= 1, '本 App 同邮箱 tester 不唯一'
        if testers:
            write('POST', f'/betaGroups/{gid}/relationships/betaTesters', {
                'data': [{'type': 'betaTesters', 'id': testers[0]['id']}]})
        else:
            write('POST', '/betaTesters', {'data': {'type': 'betaTesters', 'attributes': {'email': email},
                'relationships': {'betaGroups': {'data': [{'type': 'betaGroups', 'id': gid}]}}}})
    group_builds, _ = all_data(f'/betaGroups/{gid}/builds', {'limit': 200})
    if not any(x['id'] == BUILD for x in group_builds):
        write('POST', f'/betaGroups/{gid}/relationships/builds', {'data': [{'type': 'builds', 'id': BUILD}]})
    # 提交前再次查询，避免续跑时重复创建。
    submissions, _ = all_data('/betaAppReviewSubmissions', {'filter[build]': BUILD, 'limit': 200})
    if not submissions:
        write('POST', '/betaAppReviewSubmissions', {'data': {'type': 'betaAppReviewSubmissions',
            'relationships': {'build': {'data': {'type': 'builds', 'id': BUILD}}}}})
    final = {
        'build': get(f'/builds/{BUILD}')['data'],
        'release': get(f'/builds/{BUILD}/preReleaseVersion')['data'],
        'group': get(f'/betaGroups/{gid}')['data'],
        'testers': all_data(f'/betaGroups/{gid}/betaTesters', {'limit': 200})[0],
        'group_builds': all_data(f'/betaGroups/{gid}/builds', {'limit': 200})[0],
        'beta_review': get(f'/apps/{APP}/betaAppReviewDetail')['data'],
        'beta_app_localizations': all_data(f'/apps/{APP}/betaAppLocalizations', {'limit': 200})[0],
        'beta_build_localizations': all_data(f'/builds/{BUILD}/betaBuildLocalizations', {'limit': 200})[0],
        'beta_detail': get(f'/builds/{BUILD}/buildBetaDetail')['data'],
        'beta_submissions': all_data('/betaAppReviewSubmissions', {'filter[build]': BUILD, 'limit': 200})[0],
    }
    after = formal()
    save('formal-after.json', after)
    assert safe(after) == json.loads((ROOT / 'formal-before.json').read_text()), '正式对象有变化，需核验'
    assert all(final['beta_review']['attributes'].get(k) == v for k, v in review_copy.items())
    assert final['group']['attributes']['isInternalGroup'] is False
    assert set(EMAILS) <= {x['attributes'].get('email') for x in final['testers']}
    assert BUILD in {x['id'] for x in final['group_builds']}
    assert final['beta_detail']['attributes']['autoNotifyEnabled'] is True
    assert next(x for x in final['beta_build_localizations']
                if x['attributes']['locale'] == 'zh-Hans')['attributes']['whatsNew'] == whats_new
    assert final['beta_submissions'] and final['beta_submissions'][0]['attributes']['betaReviewState'] in (
        'WAITING_FOR_REVIEW', 'IN_REVIEW', 'APPROVED')
    final.update(formal_unchanged=True, review_copy_exact=True, whats_new_exact=True,
                 task_id='755ffd6eb22d4f908508c471cff5f506', status='done',
                 checked_at=dt.datetime.now(dt.timezone.utc).isoformat())
    save('final.json', final)
    record('completed', group_id=gid, formal_unchanged=True,
           beta_state=final['beta_submissions'][0]['attributes']['betaReviewState'])
    print(json.dumps({'status': 'done', 'group': gid,
                      'beta': final['beta_submissions'][0]['attributes'],
                      'testers': [{'id': x['id'], 'attributes': x['attributes']} for x in final['testers']],
                      'formal_unchanged': True}, ensure_ascii=False))


if __name__ == '__main__':
    main()
